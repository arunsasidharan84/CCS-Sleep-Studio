#ifndef SLEEP_EEG_H
#define SLEEP_EEG_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SleepEegPoint {
  float x;
  float y;
  int32_t channel;
} SleepEegPoint;

typedef struct SleepEegViewport {
  float sample_rate_hz;
  int32_t epoch_seconds;
  int32_t channel_count;
  int32_t point_count;
  SleepEegPoint *points;
} SleepEegViewport;

SleepEegViewport *sleep_eeg_load_viewport(const char *path);
void sleep_eeg_free_viewport(SleepEegViewport *viewport);

#ifdef __cplusplus
}
#endif

#endif
