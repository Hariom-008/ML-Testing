// engine_ncnn.mm
// iOS NCNN backend with OpenCV, aligned with Android native pipeline

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#include "ML-Testing-Bridging-Header.h"


// NCNN
#include <ncnn/net.h>
#include <ncnn/mat.h>
#include <ncnn/layer.h>

#include <vector>
#include <string>
#include <mutex>
#include <algorithm>

// OpenCV
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

//----------------------------------------------------------
// STRUCTS
//----------------------------------------------------------

struct NcnnFaceDetector {
    ncnn::Net net;
    int   inputWidth  = 320;
    int   inputHeight = 240;
    float scoreThresh = 0.6f;
    float nmsThresh   = 0.4f;
};

struct LiveModelConfig {
    float        scale;
    float        shift_x;
    float        shift_y;
    int          width;
    int          height;
    std::string  name;
    bool         org_resize;
};

struct NcnnLiveEngine {
    std::vector<ncnn::Net*>      nets;
    std::vector<LiveModelConfig> configs;

    ~NcnnLiveEngine() {
        for (auto* n : nets) {
            delete n;
        }
        nets.clear();
    }
};

//----------------------------------------------------------
// HELPERS
//----------------------------------------------------------

static NSString* bundleFile(NSString *relativePath) {
    NSString *base = [[NSBundle mainBundle] resourcePath];
    NSString *full = [base stringByAppendingPathComponent:relativePath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:full]) {
        NSLog(@"[NCNN] bundleFile: missing %@", full);
        return nil;
    }
    return full;
}

// Same logic as Android Live::CalculateBox
static cv::Rect calculate_liveness_box(
    int left,
    int top,
    int right,
    int bottom,
    int frameW,
    int frameH,
    const LiveModelConfig& cfg
) {
    int x = left;
    int y = top;
    int box_width  = right  - left + 1;
    int box_height = bottom - top  + 1;

    int shift_x = static_cast<int>(box_width  * cfg.shift_x);
    int shift_y = static_cast<int>(box_height * cfg.shift_y);

    float scale = std::min(
        cfg.scale,
        std::min(
            (frameW - 1) / (float)box_width,
            (frameH - 1) / (float)box_height
        )
    );

    int box_center_x = box_width  / 2 + x;
    int box_center_y = box_height / 2 + y;

    int new_width  = static_cast<int>(box_width  * scale);
    int new_height = static_cast<int>(box_height * scale);

    int left_top_x     = box_center_x - new_width  / 2 + shift_x;
    int left_top_y     = box_center_y - new_height / 2 + shift_y;
    int right_bottom_x = box_center_x + new_width  / 2 + shift_x;
    int right_bottom_y = box_center_y + new_height / 2 + shift_y;

    if (left_top_x < 0) {
        int s = -left_top_x;
        left_top_x     += s;
        right_bottom_x += s;
    }

    if (left_top_y < 0) {
        int s = -left_top_y;
        left_top_y     += s;
        right_bottom_y += s;
    }

    if (right_bottom_x >= frameW) {
        int s = right_bottom_x - frameW + 1;
        left_top_x     -= s;
        right_bottom_x -= s;
    }

    if (right_bottom_y >= frameH) {
        int s = right_bottom_y - frameH + 1;
        left_top_y     -= s;
        right_bottom_y -= s;
    }

    return cv::Rect(left_top_x, left_top_y, new_width, new_height);
}

// CGImage → ncnn BGR (resized)
static ncnn::Mat cgimage_to_ncnn_bgr(CGImageRef image,
                                     int targetW,
                                     int targetH)
{
    size_t width  = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    std::vector<uint8_t> rgba(width * height * 4);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgba.data(),
        width,
        height,
        8,
        width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    // Convert RGBA → BGR directly
    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        rgba.data(),
        ncnn::Mat::PIXEL_RGBA2BGR,
        (int)width,
        (int)height,
        targetW,
        targetH
    );

    return in;
}

// Treat incoming buffer as RGBA and convert to BGR (like Android Yuv420sp2bgr)
static ncnn::Mat rgba_to_ncnn_bgr(
    const void* rgbaData,
    int width,
    int height,
    int targetW,
    int targetH
)
{
    if (!rgbaData) return ncnn::Mat();

    cv::Mat rgba(height, width, CV_8UC4, const_cast<void*>(rgbaData));
    if (rgba.empty()) return ncnn::Mat();

    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);

    cv::Mat bgr_resized;
    if (width != targetW || height != targetH) {
        cv::resize(bgr, bgr_resized, cv::Size(targetW, targetH));
    } else {
        bgr_resized = bgr;
    }

    ncnn::Mat in = ncnn::Mat::from_pixels(
        bgr_resized.data,
        ncnn::Mat::PIXEL_BGR,
        bgr_resized.cols,
        bgr_resized.rows
    );

    return in;
}

static std::vector<int> nms(const std::vector<CFaceBox>& boxes, float nmsThresh) {
    std::vector<int> keep;
    std::vector<bool> removed(boxes.size(), false);

    for (size_t i = 0; i < boxes.size(); ++i) {
        if (removed[i]) continue;
        keep.push_back((int)i);

        float x1 = boxes[i].left;
        float y1 = boxes[i].top;
        float x2 = boxes[i].right;
        float y2 = boxes[i].bottom;
        float area_i = (x2 - x1 + 1) * (y2 - y1 + 1);

        for (size_t j = i + 1; j < boxes.size(); ++j) {
            if (removed[j]) continue;

            float xx1 = std::max(x1, (float)boxes[j].left);
            float yy1 = std::max(y1, (float)boxes[j].top);
            float xx2 = std::min(x2, (float)boxes[j].right);
            float yy2 = std::min(y2, (float)boxes[j].bottom);

            float w = std::max(0.0f, xx2 - xx1 + 1);
            float h = std::max(0.0f, yy2 - yy1 + 1);
            float inter = w * h;
            float area_j = (boxes[j].right - boxes[j].left + 1) *
                           (boxes[j].bottom - boxes[j].top + 1);
            float ovr = inter / (area_i + area_j - inter);

            if (ovr > nmsThresh) {
                removed[j] = true;
            }
        }
    }
    return keep;
}

// Android-like detector: input "data", output "detection_out"
static std::vector<CFaceBox> run_detector(
    NcnnFaceDetector* det,
    const ncnn::Mat& in,
    int origW,
    int origH
) {
    std::vector<CFaceBox> results;

    if (!det || in.empty()) return results;

    ncnn::Mat x = in.clone();
    const float mean_vals[3] = {104.f, 117.f, 123.f}; // BGR mean
    x.substract_mean_normalize(mean_vals, nullptr);

    ncnn::Extractor ex = det->net.create_extractor();
    ex.set_light_mode(true);

    int ret = ex.input("data", x);
    if (ret != 0) {
        NSLog(@"[NCNN] ❌ detector: failed to set input 'data' (ret=%d)", ret);
        return results;
    }

    ncnn::Mat out;
    ret = ex.extract("detection_out", out);
    if (ret != 0 || out.empty()) {
        NSLog(@"[NCNN] ❌ detector: failed to extract 'detection_out' (ret=%d)", ret);
        return results;
    }

    for (int i = 0; i < out.h; ++i) {
        const float* values = out.row(i);

        float confidence = values[1];
        if (confidence < det->scoreThresh) continue;

        float x1 = values[2] * origW;
        float y1 = values[3] * origH;
        float x2 = values[4] * origW;
        float y2 = values[5] * origH;

        CFaceBox fb;
        fb.left       = x1;
        fb.top        = y1;
        fb.right      = x2;
        fb.bottom     = y2;
        fb.confidence = confidence;
        results.push_back(fb);
    }

    auto keep = nms(results, det->nmsThresh);
    std::vector<CFaceBox> finalBoxes;
    for (int idx : keep) finalBoxes.push_back(results[idx]);

    NSLog(@"[NCNN] 🎯 Faces after NMS: %zu", finalBoxes.size());
    return finalBoxes;
}

// Liveness: single-model run, matches Android "softmax" / row(0)[1]
static float run_live_single(
    ncnn::Net* net,
    const LiveModelConfig& cfg,
    const ncnn::Mat& in
) {
    if (!net || in.empty()) {
        NSLog(@"[NCNN] ❌ Liveness: net or input is null/empty");
        return 0.0f;
    }

    ncnn::Extractor ex = net->create_extractor();
    ex.set_light_mode(true);

    int ret = ex.input("data", in);
    if (ret != 0) {
        NSLog(@"[NCNN] ❌ Liveness: failed to set input 'data' (ret=%d)", ret);
        return 0.0f;
    }

    ncnn::Mat out;

    // Try Android's name "softmax" first
    ret = ex.extract("softmax", out);

    // If that fails, auto-discover a small output blob
    if (ret != 0 || out.empty()) {
        NSLog(@"[NCNN] 🔍 Liveness: 'softmax' failed, auto-discovering output blob for model %s",
              cfg.name.c_str());

        const std::vector<ncnn::Blob>& blobs = net->blobs();
        for (size_t i = 0; i < blobs.size(); ++i) {
            const char* name = blobs[i].name.c_str();
            ncnn::Mat tmp;
            int r = ex.extract(name, tmp);
            if (r != 0 || tmp.empty()) continue;

            int len = tmp.w * tmp.h * tmp.c;
            if (len >= 2 && len <= 4) {
                out = tmp;
                ret = 0;
                NSLog(@"[NCNN] ✅ Liveness: auto-picked output blob '%s' (len=%d)", name, len);
                break;
            }
        }
    }

    if (ret != 0 || out.empty()) {
        NSLog(@"[NCNN] ❌ Liveness: failed to extract any suitable output blob (ret=%d)", ret);
        return 0.0f;
    }

    int len = out.w * out.h * out.c;
    if (len < 2) {
        NSLog(@"[NCNN] ⚠️ Liveness: output len=%d < 2, cannot read index 1", len);
        return 0.0f;
    }

    const float* row0 = out.row(0);
    float real_score = row0[1];

    NSLog(@"[NCNN] 🔴 %s softmax row0: [0]=%.3f, [1]=%.3f%s",
          cfg.name.c_str(),
          row0[0],
          row0[1],
          (len > 2 ? " (more classes hidden)" : ""));

    return real_score;
}

} // namespace

//--------------------------------------------------------------
// C API
//--------------------------------------------------------------

extern "C" {

//----------------------------------------------------------
// FACE DETECTOR
//----------------------------------------------------------

void* engine_face_detector_allocate(void) {
    auto *det = new NcnnFaceDetector();
    return det;
}

void engine_face_detector_deallocate(void* handler) {
    if (!handler) return;
    auto *det = static_cast<NcnnFaceDetector*>(handler);
    delete det;
}

int engine_face_detector_load_model(void* handler) {
    if (!handler) return -1;
    auto *det = static_cast<NcnnFaceDetector*>(handler);

    det->net.opt.num_threads = 2;
    det->net.opt.use_vulkan_compute = false;

    NSString *paramPath = bundleFile(@"detection.param");
    NSString *binPath   = bundleFile(@"detection.bin");

    NSLog(@"[NCNN] detection paramPath = %@", paramPath);
    NSLog(@"[NCNN] detection binPath   = %@", binPath);

    if (!paramPath || !binPath) return -1;

    int ret = det->net.load_param(paramPath.UTF8String);
    NSLog(@"[NCNN] load_param ret = %d", ret);
    if (ret != 0) return ret;

    ret = det->net.load_model(binPath.UTF8String);
    NSLog(@"[NCNN] load_model ret = %d", ret);
    return ret;
}

CFaceBox* engine_face_detector_detect_image(
    void* handler,
    CGImageRef image,
    int* faceCount
) {
    if (!handler || !image) return nullptr;

    auto *det = static_cast<NcnnFaceDetector*>(handler);

    int origW = (int)CGImageGetWidth(image);
    int origH = (int)CGImageGetHeight(image);

    ncnn::Mat in = cgimage_to_ncnn_bgr(image, det->inputWidth, det->inputHeight);
    auto boxes = run_detector(det, in, origW, origH);

    *faceCount = (int)boxes.size();
    if (boxes.empty()) return nullptr;

    CFaceBox* out = (CFaceBox*)malloc(sizeof(CFaceBox) * boxes.size());
    for (size_t i = 0; i < boxes.size(); ++i) out[i] = boxes[i];
    return out;
}

CFaceBox* engine_face_detector_detect_yuv(
    void* handler,
    const void* rgba,
    int width,
    int height,
    int orientation,
    int* faceCount
) {
    if (!handler || !rgba) return nullptr;
    auto *det = static_cast<NcnnFaceDetector*>(handler);

    // Convert RGBA → BGR and resize to detector input size
    ncnn::Mat in = rgba_to_ncnn_bgr(
        rgba,
        width,
        height,
        det->inputWidth,
        det->inputHeight
    );

    auto boxes = run_detector(det, in, width, height);
    *faceCount = (int)boxes.size();
    if (boxes.empty()) return nullptr;

    CFaceBox* out = (CFaceBox*)malloc(sizeof(CFaceBox) * boxes.size());
    for (size_t i = 0; i < boxes.size(); ++i) out[i] = boxes[i];
    return out;
}

void engine_face_detector_free_faces(CFaceBox* faces) {
    if (faces) free(faces);
}

//----------------------------------------------------------
// LIVE ENGINE
//----------------------------------------------------------

void* engine_live_allocate(void) {
    return new NcnnLiveEngine();
}

void engine_live_deallocate(void* handler) {
    if (!handler) return;
    delete static_cast<NcnnLiveEngine*>(handler);
}

int engine_live_load_model(
    void* handler,
    const CModelConfig* configs,
    int configCount
) {
    if (!handler || !configs || configCount <= 0) return -1;
    auto *live = static_cast<NcnnLiveEngine*>(handler);

    live->nets.clear();
    live->configs.clear();
    live->nets.reserve(configCount);
    live->configs.reserve(configCount);

    for (int i = 0; i < configCount; i++) {
        LiveModelConfig cfg;
        cfg.scale      = configs[i].scale;
        cfg.shift_x    = configs[i].shift_x;
        cfg.shift_y    = configs[i].shift_y;
        cfg.width      = configs[i].width;
        cfg.height     = configs[i].height;
        cfg.org_resize = configs[i].org_resize;
        if (configs[i].name) cfg.name = configs[i].name;

        live->configs.push_back(cfg);

        auto* net = new ncnn::Net();
        net->opt.num_threads = 2;
        net->opt.use_vulkan_compute = false;

        NSString* baseName = [NSString stringWithUTF8String:cfg.name.c_str()];

        NSString* paramPath = bundleFile([NSString stringWithFormat:@"%@.param", baseName]);
        NSString* binPath   = bundleFile([NSString stringWithFormat:@"%@.bin",   baseName]);

        NSLog(@"[NCNN] live paramPath = %@", paramPath);
        NSLog(@"[NCNN] live binPath   = %@", binPath);

        if (!paramPath || !binPath) {
            delete net;
            return -1;
        }

        int ret = net->load_param(paramPath.UTF8String);
        if (ret != 0) {
            delete net;
            return ret;
        }

        ret = net->load_model(binPath.UTF8String);
        if (ret != 0) {
            delete net;
            return ret;
        }

        live->nets.push_back(net);
    }

    return 0;
}

//------------------------------------------------------------------------------

float engine_live_detect_yuv(
    void* handler,
    const void* rgba,
    int width,
    int height,
    int orientation,
    int left,
    int top,
    int right,
    int bottom
) {
    if (!handler || !rgba) {
        NSLog(@"[NCNN] ❌ Liveness: null handler or rgba");
        return 0.0f;
    }
    auto* live = static_cast<NcnnLiveEngine*>(handler);

    if (live->nets.empty()) {
        NSLog(@"[NCNN] ❌ No liveness models loaded");
        return 0.0f;
    }

    int face_w = right - left;
    int face_h = bottom - top;
    if (face_w <= 0 || face_h <= 0) {
        NSLog(@"[NCNN] ❌ Liveness: invalid face box w=%d h=%d", face_w, face_h);
        return 0.0f;
    }

    cv::Mat frameRGBA(height, width, CV_8UC4, const_cast<void*>(rgba));
    if (frameRGBA.empty()) {
        NSLog(@"[NCNN] ❌ Liveness: frameRGBA is empty");
        return 0.0f;
    }

    cv::Mat frameBGR;
    cv::cvtColor(frameRGBA, frameBGR, cv::COLOR_RGBA2BGR);

    float sum = 0.f;
    int   valid_models = 0;

    NSLog(@"[NCNN] 🔍 Original face box: [%d,%d,%d,%d] size=%dx%d (frame %dx%d)",
          left, top, right, bottom, face_w, face_h, width, height);
    NSLog(@"[NCNN] Running %zu liveness models...", live->nets.size());

    for (int i = 0; i < (int)live->nets.size(); ++i) {
        const LiveModelConfig& cfg = live->configs[i];
        cv::Mat roi;

        if (cfg.org_resize) {
            cv::resize(frameBGR, roi, cv::Size(cfg.width, cfg.height));
        } else {
            cv::Rect rect = calculate_liveness_box(
                left, top, right, bottom,
                width, height,
                cfg
            );

            if (rect.x < 0 || rect.y < 0 ||
                rect.x + rect.width  > frameBGR.cols ||
                rect.y + rect.height > frameBGR.rows) {
                NSLog(@"[NCNN] ⚠️ Model %s: ROI out of bounds [%d,%d,%d,%d]",
                      cfg.name.c_str(), rect.x, rect.y,
                      rect.x + rect.width, rect.y + rect.height);
                continue;
            }

            cv::Mat face = frameBGR(rect).clone();
            if (face.empty()) {
                NSLog(@"[NCNN] ⚠️ Model %s: empty face ROI", cfg.name.c_str());
                continue;
            }

            cv::resize(face, roi, cv::Size(cfg.width, cfg.height));
        }

        if (roi.empty()) {
            NSLog(@"[NCNN] ⚠️ Model %s: empty roi after resize", cfg.name.c_str());
            continue;
        }

        ncnn::Mat in = ncnn::Mat::from_pixels(
            roi.data,
            ncnn::Mat::PIXEL_BGR,
            roi.cols,
            roi.rows
        );

        float score = run_live_single(live->nets[i], cfg, in);
        NSLog(@"[NCNN] ✅ Model %s liveness score: %.3f",
              cfg.name.c_str(), score);

        sum += score;
        valid_models++;
    }

    if (valid_models == 0) {
        NSLog(@"[NCNN] ❌ No valid liveness models processed");
        return 0.0f;
    }

    float avgScore = sum / valid_models;
    NSLog(@"[NCNN] 🎯 Final liveness score: %.3f (avg of %d models)",
          avgScore, valid_models);
    NSLog(@"[NCNN] 💡 Interpretation: %.3f = %s",
          avgScore,
          avgScore > 0.5f ? "REAL FACE ✅" : "FAKE/SPOOF ❌");

    return avgScore;
}

} // extern "C"
