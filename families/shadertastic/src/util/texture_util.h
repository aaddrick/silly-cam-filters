#ifndef TEXTURE_UTIL_H
#define TEXTURE_UTIL_H

#include <obs-module.h>
#include <opencv2/core/mat.hpp>

void render_texture(gs_texture_t *final_tex, bool use_copy, bool compensate_alpha);

#ifdef DEV_MODE
cv::Mat extractImage(gs_texture_t *tex);
bool saveMat(cv::Mat &src, std::string path);
#endif

#endif // TEXTURE_UTIL_H
