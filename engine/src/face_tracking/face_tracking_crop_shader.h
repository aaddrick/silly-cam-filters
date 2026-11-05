/******************************************************************************
    Copyright (C) 2023 by xurei <xureilab@gmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
******************************************************************************/

#ifndef SHADERTASTIC_FACE_TRACKING_CROP_SHADER_H
#define SHADERTASTIC_FACE_TRACKING_CROP_SHADER_H

#include <graphics/graphics.h>
#include <opencv2/core.hpp>
#include "../util/tuple.h"

class FaceTrackingCropShader {
private:
    gs_texrender_t *crop_texrender;
    gs_stagesurf_t *staging_texture = nullptr;
    static gs_effect_t *gs_crop_effect;
    static gs_eparam_t *gs_crop_param_center;
    static gs_eparam_t *gs_crop_param_crop_size;
    static gs_eparam_t *gs_crop_param_rotation;
    static gs_eparam_t *gs_crop_param_aspect_ratio;

public:
    static void init();
    static void release();
    FaceTrackingCropShader();
    ~FaceTrackingCropShader();

    cv::Mat getCroppedImage(gs_texture_t *source_tex, float2 &roi_center, float2 &roi_size, float rotation);
};

#endif // SHADERTASTIC_FACE_TRACKING_CROP_SHADER_H
