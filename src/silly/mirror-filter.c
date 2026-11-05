/*
 * Silly Mirror: the smallest complete filter in this plugin.
 * Copy this file to start a new filter. See README.md, "Add a filter".
 *
 * 1. Shader:   data/silly/mirror.effect
 * 2. Text:     data/locale/en-US.ini (SillyMirror.*)
 * 3. Register: src/silly/silly-filters.c
 */
#include <obs-module.h>

struct mirror_filter {
	obs_source_t *context;
	gs_effect_t *effect;
	gs_eparam_t *param_mode;
	int mode;
};

static const char *mirror_get_name(void *type_data)
{
	UNUSED_PARAMETER(type_data);
	return obs_module_text("SillyMirror.Name");
}

static void mirror_update(void *data, obs_data_t *settings)
{
	struct mirror_filter *f = data;
	f->mode = (int)obs_data_get_int(settings, "mode");
}

static void *mirror_create(obs_data_t *settings, obs_source_t *source)
{
	struct mirror_filter *f = bzalloc(sizeof(*f));
	f->context = source;

	char *path = obs_module_file("silly/mirror.effect");
	obs_enter_graphics();
	f->effect = gs_effect_create_from_file(path, NULL);
	obs_leave_graphics();
	bfree(path);

	if (!f->effect) {
		blog(LOG_ERROR, "[silly-cam-filters] Silly Mirror: cannot load silly/mirror.effect");
		bfree(f);
		return NULL;
	}
	f->param_mode = gs_effect_get_param_by_name(f->effect, "mode");

	mirror_update(f, settings);
	return f;
}

static void mirror_destroy(void *data)
{
	struct mirror_filter *f = data;
	obs_enter_graphics();
	gs_effect_destroy(f->effect);
	obs_leave_graphics();
	bfree(f);
}

static void mirror_render(void *data, gs_effect_t *effect)
{
	UNUSED_PARAMETER(effect);
	struct mirror_filter *f = data;

	if (!obs_source_process_filter_begin(f->context, GS_RGBA, OBS_ALLOW_DIRECT_RENDERING))
		return;
	gs_effect_set_int(f->param_mode, f->mode);
	obs_source_process_filter_end(f->context, f->effect, 0, 0);
}

static obs_properties_t *mirror_properties(void *data)
{
	UNUSED_PARAMETER(data);
	obs_properties_t *props = obs_properties_create();
	obs_property_t *p = obs_properties_add_list(props, "mode", obs_module_text("SillyMirror.Mode"),
						    OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
	obs_property_list_add_int(p, obs_module_text("SillyMirror.Mode.LeftRight"), 0);
	obs_property_list_add_int(p, obs_module_text("SillyMirror.Mode.RightLeft"), 1);
	obs_property_list_add_int(p, obs_module_text("SillyMirror.Mode.TopBottom"), 2);
	obs_property_list_add_int(p, obs_module_text("SillyMirror.Mode.FourWay"), 3);
	return props;
}

static void mirror_defaults(obs_data_t *settings)
{
	obs_data_set_default_int(settings, "mode", 0);
}

struct obs_source_info silly_mirror_filter = {
	.id = "silly_mirror_filter",
	.type = OBS_SOURCE_TYPE_FILTER,
	.output_flags = OBS_SOURCE_VIDEO,
	.get_name = mirror_get_name,
	.create = mirror_create,
	.destroy = mirror_destroy,
	.update = mirror_update,
	.video_render = mirror_render,
	.get_properties = mirror_properties,
	.get_defaults = mirror_defaults,
};
