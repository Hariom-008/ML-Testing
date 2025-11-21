//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//
#import "OpenCVWrapper.h"
#import "bch_codec.h"


#ifndef SpoofDetect_Bridging_Header_h
#define SpoofDetect_Bridging_Header_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>


#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int left;
    int top;
    int right;
    int bottom;
    float confidence;
} CFaceBox;

typedef struct {
    float scale;
    float shift_x;
    float shift_y;
    int height;
    int width;
    const char* name;
    bool org_resize;
} CModelConfig;

// Face Detector
void* engine_face_detector_allocate(void);
void engine_face_detector_deallocate(void* handler);
int engine_face_detector_load_model(void* handler);

CFaceBox* engine_face_detector_detect_image(
    void* handler,
    CGImageRef image,
    int* faceCount
);

CFaceBox* engine_face_detector_detect_yuv(
    void* handler,
    const void* yuv,
    int width,
    int height,
    int orientation,
    int* faceCount
);

void engine_face_detector_free_faces(CFaceBox* faces);

// Live Engine
void* engine_live_allocate(void);
void engine_live_deallocate(void* handler);

int engine_live_load_model(
    void* handler,
    const CModelConfig* configs,
    int configCount
);

float engine_live_detect_yuv(
    void* handler,
    const void* yuv,
    int width,
    int height,
    int orientation,
    int left,
    int top,
    int right,
    int bottom
);

#ifdef __cplusplus
}
#endif

#endif /* SpoofDetect_Bridging_Header_h */
