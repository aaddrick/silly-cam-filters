#ifndef SHADERTASTIC_DEBUG_UTIL_HPP
#define SHADERTASTIC_DEBUG_UTIL_HPP

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#include <obs-module.h>
#include <opencv2/core/mat.hpp>

int __debug_get_opencv_format(const gs_color_format obs_format) {
	switch (obs_format) {
		case GS_UNKNOWN: return -1;
		case GS_A8:
		case GS_R8: return CV_8UC1;
		case GS_RGBA:
		case GS_BGRX:
		case GS_BGRA: return CV_8UC4;
			break;
		case GS_R10G10B10A2: return CV_32SC4;
		case GS_RGBA16: return CV_16UC4;
		case GS_R16: return CV_16UC1;
		case GS_RGBA16F: return CV_16FC4;
		case GS_RGBA32F: return CV_32FC4;
		case GS_RG16F: return CV_16FC2;
		case GS_RG32F: return CV_32FC2;
		case GS_R16F: return CV_16FC1;
		case GS_R32F: return CV_32FC1;
		default: return -1;
	}
}

void __debug_save_texture_png(gs_stagesurf_t *stagesurf, uint32_t cx, uint32_t cy, const char* path) {
    uint8_t *videoData;
	uint32_t videoLinesize = 0;

	auto color_format = gs_stagesurface_get_color_format(stagesurf);
	int opencv_format = __debug_get_opencv_format(color_format);

    if (gs_stagesurface_map(stagesurf, &videoData, &videoLinesize)) {
	    //gs_texture_map(texture, videoData, &videoLinesize);
    	//stbi_write_png(path, (int)cx, (int)cy, 4, videoData, 0);
    	cv::Mat imageRGBA(cy, cx, opencv_format, videoData);

    	cv::Mat out;
    	imageRGBA.convertTo(out, CV_8UC4, 1.0/256.0);
    	stbi_write_png(path, (int)cx, (int)cy, 4, out.data, 0);

    	//cv::imwrite(path, imageRGBA);

    	gs_stagesurface_unmap(stagesurf);
    }
}
void __debug_save_texture_png(gs_texture_t *texture, const char* path) {
	obs_enter_graphics();
	const uint32_t cx = gs_texture_get_width(texture);
	const uint32_t cy = gs_texture_get_height(texture);
	gs_stagesurf_t *stagesurf = gs_stagesurface_create(cx, cy, gs_texture_get_color_format(texture));
	gs_stage_texture(stagesurf, texture);

	__debug_save_texture_png(stagesurf, cx, cy, path);

	gs_stagesurface_destroy(stagesurf);
	obs_leave_graphics();
}

static void __debug_log_properties(obs_properties_t *props) {
	obs_property_t *prop = obs_properties_first(props);

	while (prop) {
		const char *name = obs_property_name(prop);
		const char *desc = obs_property_description(prop);
		enum obs_property_type type = obs_property_get_type(prop);

		const char *type_str = "unknown";
		switch (type) {
			case OBS_PROPERTY_INVALID:      type_str = "invalid"; break;
			case OBS_PROPERTY_BOOL:         type_str = "bool"; break;
			case OBS_PROPERTY_INT:          type_str = "int"; break;
			case OBS_PROPERTY_FLOAT:        type_str = "float"; break;
			case OBS_PROPERTY_TEXT:         type_str = "text"; break;
			case OBS_PROPERTY_PATH:         type_str = "path"; break;
			case OBS_PROPERTY_LIST:         type_str = "list"; break;
			case OBS_PROPERTY_COLOR:        type_str = "color"; break;
			case OBS_PROPERTY_BUTTON:       type_str = "button"; break;
			case OBS_PROPERTY_FONT:         type_str = "font"; break;
			case OBS_PROPERTY_EDITABLE_LIST:type_str = "editable_list"; break;
			case OBS_PROPERTY_FRAME_RATE:   type_str = "framerate"; break;
			case OBS_PROPERTY_GROUP:        type_str = "group"; break;
			case OBS_PROPERTY_COLOR_ALPHA:  type_str = "color_alpha"; break;
		}

		blog(LOG_INFO, "Property: name='%s', type=%s, desc='%s'",
			name ? name : "(null)",
			type_str,
			desc ? desc : "(null)");

		// If this property is a group, recursively list its children
		if (type == OBS_PROPERTY_GROUP) {
			obs_properties_t *subprops = obs_property_group_content(prop);
			if (subprops) {
				__debug_log_properties(subprops);
			}
		}

		bool isok = obs_property_next(&prop);
		if (!isok) {
			prop = nullptr;
		}
	}
}

#endif // SHADERTASTIC_DEBUG_UTIL_HPP
