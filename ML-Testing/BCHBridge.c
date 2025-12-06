// BCHBridge.c
#include "bch_codec.h"

#ifdef __cplusplus
extern "C" {
#endif

int bch_get_ecc_bits_bridge(struct bch_control *bch) {
    return bch ? (int)bch->ecc_bits : -1;
}

#ifdef __cplusplus
}
#endif
