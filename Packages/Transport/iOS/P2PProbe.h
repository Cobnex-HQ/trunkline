#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*TrunklineP2PCallback)(const char *event_json);
void trunkline_p2p_prepare(void);
int32_t trunkline_p2p_session(const char *config_json, const char *helper, void (*callback)(const char *));
void trunkline_p2p_stop(void);
int32_t trunkline_p2p_run(const char *config_path, const char *helper, TrunklineP2PCallback callback);
#ifdef __cplusplus
}
#endif
