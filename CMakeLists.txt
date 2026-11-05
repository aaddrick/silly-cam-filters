cmake_minimum_required(VERSION 3.28...3.30)

# Build system based on the OBS plugin template, as used by obs-shadertastic.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/common/bootstrap.cmake" NO_POLICY_SCOPE)

project(${_name} VERSION ${_version} LANGUAGES C CXX)

include(compilerconfig)
include(defaults)
include(helpers)

# The plugin links static OpenCV and libzip into a shared module.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(${CMAKE_PROJECT_NAME} MODULE)
# Upstream family code has warnings; do not fail the build on them.
set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES COMPILE_WARNING_AS_ERROR OFF)

find_package(libobs REQUIRED)
find_package(obs-frontend-api REQUIRED)
find_package(jansson REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Widgets Core)

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs OBS::obs-frontend-api jansson::jansson Qt6::Core
                                                    Qt6::Widgets)
set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON)

# ---------------------------------------------------------------------------
# Module core and our own filters
# ---------------------------------------------------------------------------
file(GLOB silly_SOURCES CONFIGURE_DEPENDS "src/silly/*.c")
target_sources(${CMAKE_PROJECT_NAME} PRIVATE src/plugin.c src/scf-family.c src/scf-family.h ${silly_SOURCES})
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE src)

# ---------------------------------------------------------------------------
# Filter families
#
# scf_add_family(<family> <sources...>) compiles the sources with their OBS
# module hooks renamed to scf_<family>_*. src/scf-family.c then sends each
# family to its own folder in data/. See src/scf-family.h.
# ---------------------------------------------------------------------------
set(SCF_RENAMED_HOOKS
    obs_module_load
    obs_module_unload
    obs_module_post_load
    obs_module_set_locale
    obs_module_free_locale
    obs_module_lookup
    obs_module_text
    obs_module_get_string
    obs_module_set_pointer
    obs_current_module
    obs_module_ver
    obs_module_name
    obs_module_description
    obs_module_author
    obs_module_load_locale
    obs_find_module_file
    obs_module_get_config_path
    obs_get_module_data_path)

function(scf_add_family family)
  set(defs "")
  foreach(hook IN LISTS SCF_RENAMED_HOOKS)
    string(REPLACE "obs_module_" "" short "${hook}")
    string(REPLACE "obs_" "" short "${short}")
    list(APPEND defs "${hook}=scf_${family}_${short}")
  endforeach()
  set_source_files_properties(${ARGN} TARGET_DIRECTORY ${CMAKE_PROJECT_NAME} PROPERTIES COMPILE_DEFINITIONS "${defs}")
  target_sources(${CMAKE_PROJECT_NAME} PRIVATE ${ARGN})
endfunction()

# --- shaderfilter (exeldro/obs-shaderfilter) -------------------------------
scf_add_family(shaderfilter families/shaderfilter/obs-shaderfilter.c)

# --- retro (FiniteSingularity/obs-retro-effects) ----------------------------
file(GLOB_RECURSE retro_SOURCES CONFIGURE_DEPENDS "families/retro-effects/*.c")
scf_add_family(retro ${retro_SOURCES})
# Both shaderfilter and retro define this helper; give retro its own copy.
set_property(SOURCE ${retro_SOURCES} TARGET_DIRECTORY ${CMAKE_PROJECT_NAME} APPEND PROPERTY COMPILE_DEFINITIONS
             create_or_reset_texrender=scf_retro_create_or_reset_texrender)

# --- engine (grew out of xurei/obs-shadertastic) ----------------------------
file(GLOB_RECURSE shadertastic_SOURCES CONFIGURE_DEPENDS "engine/src/*.cpp")
list(FILTER shadertastic_SOURCES EXCLUDE REGEX "win_dll_overrides\\.cpp$")
file(GLOB onnxmediapipe_SOURCES CONFIGURE_DEPENDS "engine/onnxmediapipe/src/*.cpp"
     "engine/onnxmediapipe/src/filtering/*.cpp")
scf_add_family(engine ${shadertastic_SOURCES} ${onnxmediapipe_SOURCES})
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE engine engine/onnxmediapipe/include)
target_compile_definitions(${CMAKE_PROJECT_NAME} PRIVATE DISABLE_ONNXRUNTIME_GPU)

# ONNX Runtime (shared, installed next to the plugin) and OpenCV (static).
include(cmake/FetchOnnxruntime.cmake)
include(cmake/FetchOpenCV.cmake)
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OpenCV)
set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES BUILD_RPATH "${onnxruntime_SOURCE_DIR}/lib")

# libzip (static) for shadertastic effect bundles.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libs" FORCE)
set(BUILD_DOC OFF CACHE BOOL "" FORCE)
set(BUILD_REGRESS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUILD_OSSFUZZ OFF CACHE BOOL "" FORCE)
set(ENABLE_COMMONCRYPTO OFF CACHE BOOL "" FORCE)
set(ENABLE_GNUTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_BZIP2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(LIBZIP_DO_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)
add_subdirectory(vendor/libzip EXCLUDE_FROM_ALL)
target_compile_options(zip PRIVATE -w)
find_package(ZLIB REQUIRED)
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE zip ZLIB::ZLIB)

# ---------------------------------------------------------------------------
set_target_properties_plugin(${CMAKE_PROJECT_NAME} PROPERTIES OUTPUT_NAME ${_name})

# The onnxruntime library ships as libonnxruntime.so.<version>, in
# <libdir>/obs-plugins/silly-cam-filters/. Point the plugin at that exact file.
add_custom_command(
  TARGET ${CMAKE_PROJECT_NAME}
  POST_BUILD
  COMMAND patchelf --replace-needed libonnxruntime.so.1 libonnxruntime.so.${Onnxruntime_VERSION}
          $<TARGET_FILE:${CMAKE_PROJECT_NAME}>
  COMMENT "Pointing the plugin at libonnxruntime.so.${Onnxruntime_VERSION}")
