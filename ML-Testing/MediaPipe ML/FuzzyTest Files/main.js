const fs = require('fs');
const path = require('path');
const CryptoJS = require('crypto-js');
const { createBCHContext } = require('./native/bch');

const TARGET_DISTANCE_COUNT = 317;
const ERROR_CORRECTION_RATE = 0.02;

// Default Quantization Parameters
const DEFAULT_QUANT_PARAMS = {
    scale: 256,           // 256 bins (0.00-0.08 range) - more sensitive
    bitsPerDistance: 8,   // 8 bits per distance
    maxDistance: 2.0    // Maximum expected distance (adjusted for your data)
};

const BCH_CONTEXT = createBCHContext({
    distanceCount: TARGET_DISTANCE_COUNT,
    bitsPerDistance: DEFAULT_QUANT_PARAMS.bitsPerDistance,
    errorRate: ERROR_CORRECTION_RATE
});
const ENROLLMENT_STORE_PATH = path.join(__dirname, 'enrollments.json');

// Surface BCH metadata for reference/logging
const DEFAULT_ECC_PARAMS = {
    scheme: 'BCH',
    n: BCH_CONTEXT.n,
    k: BCH_CONTEXT.dataBits,
    t: BCH_CONTEXT.t
};

function ensureDistanceVector(distances) {
    if (!Array.isArray(distances)) {
        throw new Error('Distance vector must be an array');
    }
    if (distances.length !== TARGET_DISTANCE_COUNT) {
        throw new Error(`Distance vector must have ${TARGET_DISTANCE_COUNT} values. Received ${distances.length}.`);
    }
    return distances;
}

function bitStringToUint8Array(bits) {
    const buffer = Buffer.alloc(bits.length);
    for (let i = 0; i < bits.length; i++) {
        buffer[i] = bits[i] === '1' ? 1 : 0;
    }
    return buffer;
}

function uint8ArrayToBitString(arr) {
    let out = '';
    for (let i = 0; i < arr.length; i++) {
        out += arr[i] ? '1' : '0';
    }
    return out;
}

function randomBitString(length) {
    const byteLength = Math.ceil(length / 8);
    const hex = CryptoJS.lib.WordArray.random(byteLength).toString();
    const bits = hex.split('').map((char) => parseInt(char, 16).toString(2).padStart(4, '0')).join('');
    if (bits.length === length) {
        return bits;
    }
    if (bits.length > length) {
        return bits.slice(0, length);
    }
    return bits.padEnd(length, '0');
}

function bitsToHex(bits) {
    if (!bits) {
        return '';
    }
    return BigInt(`0b${bits}`).toString(16);
}

function countBitErrors(expectedBits, observedBits) {
    const length = Math.min(expectedBits.length, observedBits.length);
    let errors = 0;
    for (let i = 0; i < length; i++) {
        if (expectedBits[i] !== observedBits[i]) {
            errors++;
        }
    }
    errors += Math.abs(expectedBits.length - observedBits.length);
    return errors;
}

function totalDistanceDifference(a, b) {
    const length = Math.min(a.length, b.length);
    let total = 0;
    for (let i = 0; i < length; i++) {
        total += Math.abs(a[i] - b[i]);
    }
    return total;
}

function logBits(label, bitString, previewLength = 64) {
    if (!bitString) {
        console.log(`${label}: <empty>`);
        return;
    }
    const preview = bitString.substring(0, previewLength);
    console.log(`${label}: length=${bitString.length}, first ${previewLength} bits=${preview}`);
}

class FuzzyExtractorService {
    static extractDistancesFromBits(bits, params) {
        const { scale, maxDistance, bitsPerDistance } = params;
        const distances = [];
        for (let i = 0; i < bits.length; i += bitsPerDistance) {
            const bitChunk = bits.substring(i, i + bitsPerDistance);
            if (bitChunk.length === bitsPerDistance) {
                const binIndex = parseInt(bitChunk, 2);
                const distance = (binIndex / scale) * maxDistance; distances.push(distance);
            }
        } return distances;
    }
    static calculateOptimalECCParams() {
        return DEFAULT_ECC_PARAMS;
    }

    static quantizeDistances(distances, params = DEFAULT_QUANT_PARAMS) {
        const { scale, maxDistance } = params;

        // console.log(`[FuzzyExtractor] Quantizing distances with params: scale=${scale}, maxDistance=${maxDistance}`);
        // console.log(`[FuzzyExtractor] Input distances: [${distances.join(', ')}]`);

        const result = distances.map((distance, index) => {
            const clampedDistance = Math.max(0, Math.min(maxDistance, distance));
            const binIndex = Math.floor((clampedDistance / maxDistance) * scale);
            const clampedBinIndex = Math.max(0, Math.min(scale - 1, binIndex));
            const binary = clampedBinIndex.toString(2).padStart(params.bitsPerDistance, '0');

            // console.log(`[FuzzyExtractor] Distance ${index}: ${distance} -> clamped: ${clampedDistance} -> bin: ${clampedBinIndex} -> binary: ${binary}`);

            return binary;
        }).join('');

        // console.log(`[FuzzyExtractor] Final quantized string: ${result}`);
        return result;
    }

    static padBitsToDataLength(bitString) {
        if (bitString.length === BCH_CONTEXT.dataBits) {
            return bitString;
        }
        if (bitString.length > BCH_CONTEXT.dataBits) {
            return bitString.slice(0, BCH_CONTEXT.dataBits);
        }
        return bitString.padEnd(BCH_CONTEXT.dataBits, '0');
    }

    static buildCodeword(bitString) {
        const paddedBits = this.padBitsToDataLength(bitString);
        const eccBits = uint8ArrayToBitString(BCH_CONTEXT.encodeBits(bitStringToUint8Array(paddedBits)));
        return {
            paddedBits,
            eccBits,
            codeword: paddedBits + eccBits
        };
    }

    static buildCodewordFromDistances(distances, quantParams) {
        const validated = ensureDistanceVector(distances);
        const quantizedBits = this.quantizeDistances(validated, quantParams);
        return this.buildCodeword(quantizedBits);
    }

    static xorStrings(str1, str2) {
        const maxLength = Math.max(str1.length, str2.length);

        let result = '';
        for (let i = 0; i < maxLength; i++) {
            result += str1[i] === str2[i] ? '0' : '1';
        }

        return result;
    }

    static generate(distances, quantParams = DEFAULT_QUANT_PARAMS) {
        const { paddedBits, codeword } = this.buildCodewordFromDistances(distances, quantParams);
        const secretBits = randomBitString(codeword.length);
        const helper = this.xorStrings(codeword, secretBits);
        const secretHex = bitsToHex(secretBits);

        return {
            R: secretBits,
            RHash: secretHex,
            RH: secretHex.substring(0, 63),
            helper: `${helper}|${paddedBits}`
        };
    }

    static reproduce(distances, helper, quantParams = DEFAULT_QUANT_PARAMS) {
        // console.log(`[FuzzyExtractor] Reproducing with ${distances.length} distances`);

        const parts = helper.split("|");
        let originalHelper;
        let enrollmentBits;

        if (parts.length === 2) {
            originalHelper = parts[0];
            enrollmentBits = parts[1];
        } else {
            originalHelper = helper;
            return this.reproduceLegacy(distances, helper, quantParams, eccParams);
        }

        const { paddedBits, codeword } = this.buildCodewordFromDistances(distances, quantParams);



        let bitErrors = 0;
        for (let i = 0; i < Math.min(enrollmentBits.length, paddedBits.length); i++) {
            if (enrollmentBits[i] !== paddedBits[i]) {
                bitErrors++;
            }
        }

        // console.log("Bit Errors:", bitErrors);

        const enrollmentDistances = this.extractDistancesFromBits(enrollmentBits, quantParams);
        const verificationDistances = this.extractDistancesFromBits(paddedBits, quantParams);

        let totalDistanceDiff = 0;
        for (let i = 0; i < Math.min(enrollmentDistances.length, verificationDistances.length); i++) {
            totalDistanceDiff += Math.abs(enrollmentDistances[i] - verificationDistances[i]);
        }

        // console.log("Total Distance Difference:", totalDistanceDiff);

        const bitErrorRate = bitErrors / enrollmentBits.length;

        // --- Average per-distance difference check ---
        const avgDistDiff = totalDistanceDiff / enrollmentDistances.length;

        // Thresholds (tune these for your data)
        const MAX_BIT_ERROR_RATE = ERROR_CORRECTION_RATE;
        const MAX_AVG_DIST_DIFF = 0.02;

        if (bitErrorRate > MAX_BIT_ERROR_RATE) {
            // console.log(" Rejected: too many bit errors:", bitErrorRate);
            return null;
        }

        if (avgDistDiff > MAX_AVG_DIST_DIFF) {
            // console.log(" Rejected: distance difference too high:", avgDistDiff);
            return null;
        }

        // If passes both checks, continue normal
        const recoveredBits = this.xorStrings(originalHelper, codeword);
        return recoveredBits;

        // if (bitErrors <= eccParams.t) {
        //     console.log("bitErrors", bitErrors)
        //     if (totalDistanceDiff > 0.05) {
        //         return null;
        //     }
        //     const codeword = this.generateBCH(enrollmentBits, eccParams);
        //     // console.log("Codeword (BCH):", codeword);

        //     const RHash = this.xorStrings(originalHelper, codeword);
        //     // console.log("XOR of Helper and Codeword (RHash):", RHash);

        //     const recoveredRHex = BigInt('0b' + RHash).toString(16);
        //     // console.log("Recovered R (Hex):", recoveredRHex);
        //     if (recoveredRHex.length === 63)
        //         return recoveredRHex.substring(0, 62);
        //     return recoveredRHex.substring(1, 63);
        // } else {
        //     return null;
        // }
    }


    static reproduceLegacy(distances, helper, quantParams = DEFAULT_QUANT_PARAMS) {
        const { codeword } = this.buildCodewordFromDistances(distances, quantParams);

        const RHash = this.xorStrings(helper, codeword);

        const enrollmentCodeword = this.xorStrings(helper, RHash);

        let codewordBitErrors = 0;
        for (let i = 0; i < Math.min(enrollmentCodeword.length, codeword.length); i++) {
            if (enrollmentCodeword[i] !== codeword[i]) {
                codewordBitErrors++;
            }
        }

        const maxAllowedCodewordErrors = DEFAULT_ECC_PARAMS.t * 2;

        const totalDistanceDiff = this.calculateTotalDistanceDifference(distances, helper, quantParams);

        return null;
    }

    // Add missing methods (extractDistancesFromBits, calculateTotalDistanceDifference) based on your application logic
}



module.exports = {
    FuzzyExtractorService,
    DEFAULT_QUANT_PARAMS,
    DEFAULT_ECC_PARAMS,
    BCH_CONTEXT,
    TARGET_DISTANCE_COUNT,
    enrollDistanceSets,
    verifyAgainstEnrollments,
    processDistanceSets,
    loadEnrollmentStore,
    saveEnrollmentStore,
    ENROLLMENT_STORE_PATH
};

if (require.main === module) {
    const registrationSample = [];
    const verificationSample = [];
    const storedEnrollments = loadEnrollmentStore();

    if (storedEnrollments && storedEnrollments.length) {
        console.log(`Loaded ${storedEnrollments.length} enrollment(s) from ${ENROLLMENT_STORE_PATH}`);
        if (verificationSample.length) {
            const comparisons = verifyAgainstEnrollments(storedEnrollments, verificationSample);
            comparisons.forEach((result) => {
                console.log(`\n--- Verification: Enrollment #${result.enrollmentIndex} vs Verification #${result.verificationIndex} ---`);
                const deltaLabel = typeof result.distanceDelta === 'number'
                    ? result.distanceDelta.toFixed(6)
                    : 'n/a';
                console.log(`Distance delta sum: ${deltaLabel}`);
                console.log(`Bit errors vs enrollment: ${result.bitErrors} (${(result.bitErrorRate * 100).toFixed(2)}%)`);
                console.log(`Pre-correction hex: ${result.preCorrectionHex}`);
                if (result.success) {
                    console.log(`Recovered hex: ${result.recoveredHex}`);
                    console.log(`Matches enrollment(secret)? ${result.match ? 'yes' : 'no'}`);
                } else {
                    console.log('BCH reproduction failed: thresholds exceeded');
                }
            });
        } else {
            console.log('Provide verification samples in main.js to run comparisons, or call processDistanceSets(reg, ver) from another script.');
        }
    } else if (registrationSample.length && verificationSample.length) {
        const { enrollments, comparisons } = processDistanceSets(registrationSample, verificationSample);
        saveEnrollmentStore(enrollments);
        console.log(`\nEnrollment data saved to ${ENROLLMENT_STORE_PATH}. Delete this file to force new helpers/RHashes.`);
    } else {
        console.log('No enrollments stored and no registration data provided.');
        console.log('Populate registrationSample & verificationSample arrays in main.js or require this module and call processDistanceSets(reg, ver).');
    }
}

function loadEnrollmentStore(filePath = ENROLLMENT_STORE_PATH) {
    if (!fs.existsSync(filePath)) {
        return null;
    }
    try {
        const raw = fs.readFileSync(filePath, 'utf8');
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed.enrollments)) {
            return parsed.enrollments;
        }
        if (Array.isArray(parsed)) {
            return parsed;
        }
    } catch (error) {
        console.error(`Failed to parse enrollment store ${filePath}:`, error.message);
    }
    return null;
}

function saveEnrollmentStore(enrollments, filePath = ENROLLMENT_STORE_PATH) {
    try {
        const payload = {
            savedAt: new Date().toISOString(),
            enrollments
        };
        fs.writeFileSync(filePath, JSON.stringify(payload, null, 2));
    } catch (error) {
        console.error(`Failed to save enrollment store ${filePath}:`, error.message);
    }
}

function enrollDistanceSets(registrationSets = [], quantParams = DEFAULT_QUANT_PARAMS) {
    return registrationSets.map((distances, index) => {
        ensureDistanceVector(distances);
        const record = FuzzyExtractorService.generate(distances, quantParams);
        const [helperBits, enrollmentBits] = record.helper.split('|');

        return {
            index,
            helper: record.helper,
            helperBits,
            enrollmentBits,
            secretBits: record.R,
            secretHex: record.RHash
        };
    });
}

function verifyAgainstEnrollments(enrollments, verificationSets = [], quantParams = DEFAULT_QUANT_PARAMS) {
    const comparisons = [];

    enrollments.forEach((enrollment) => {
        verificationSets.forEach((verificationDistances, verificationIndex) => {
            ensureDistanceVector(verificationDistances);
            const distances = verificationDistances;
            const scenario = FuzzyExtractorService.buildCodewordFromDistances(distances, quantParams);
            const bitErrors = countBitErrors(enrollment.enrollmentBits, scenario.paddedBits);
            const bitErrorRate = enrollment.enrollmentBits.length
                ? bitErrors / enrollment.enrollmentBits.length
                : 0;
            const distanceDelta = null;
            const preCorrectionBits = FuzzyExtractorService.xorStrings(enrollment.helperBits, scenario.codeword);
            const preCorrectionHex = bitsToHex(preCorrectionBits);
            const recoveredBits = FuzzyExtractorService.reproduce(distances, enrollment.helper, quantParams);
            const recoveredHex = recoveredBits ? bitsToHex(recoveredBits) : null;
            const match = Boolean(recoveredHex && recoveredHex === enrollment.secretHex);

            comparisons.push({
                enrollmentIndex: enrollment.index,
                verificationIndex,
                bitErrors,
                bitErrorRate,
                distanceDelta,
                preCorrectionHex,
                recoveredHex,
                match,
                success: Boolean(recoveredHex)
            });
        });
    });

    return comparisons;
}

function processDistanceSets(registrationSets = [], verificationSets = [], options = {}) {
    const quantParams = options.quantParams || DEFAULT_QUANT_PARAMS;
    const enrollments = enrollDistanceSets(registrationSets, quantParams);
    const comparisons = verifyAgainstEnrollments(enrollments, verificationSets, quantParams);

    if (options.log !== false) {
        enrollments.forEach((enrollment) => {
            console.log(`\n=== Enrollment #${enrollment.index} ===`);
            console.log(`Secret hex (RHash): ${enrollment.secretHex}`);
            console.log(`Helper length: ${enrollment.helperBits.length} bits`);
        });

        comparisons.forEach((result) => {
            console.log(`\n--- Verification: Enrollment #${result.enrollmentIndex} vs Verification #${result.verificationIndex} ---`);
            const deltaLabel = typeof result.distanceDelta === 'number'
                ? result.distanceDelta.toFixed(6)
                : 'n/a';
            console.log(`Distance delta sum: ${deltaLabel}`);
            console.log(`Bit errors vs enrollment: ${result.bitErrors} (${(result.bitErrorRate * 100).toFixed(2)}%)`);
            console.log(`Pre-correction hex: ${result.preCorrectionHex}`);
            if (result.success) {
                console.log(`Recovered hex: ${result.recoveredHex}`);
                console.log(`Matches enrollment secret? ${result.match ? 'yes' : 'no'}`);
            } else {
                console.log('BCH reproduction failed: thresholds exceeded');
            }
        });
    }

    return { enrollments, comparisons };
}
