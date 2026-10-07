cmake_minimum_required(VERSION 3.17)
project(paper_front_kernels LANGUAGES CXX)
set(GODOTCPP_TARGET template_release CACHE STRING "" FORCE)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "" FORCE)
add_subdirectory(vendor)
add_library(paper_front_kernels SHARED src/kernels.cpp)
target_link_libraries(paper_front_kernels PRIVATE godot::cpp)
target_compile_features(paper_front_kernels PRIVATE cxx_std_17)
# Preserve float ordering and exact-distance ties; never enable fast-math.
target_compile_options(paper_front_kernels PRIVATE -O3 -ffp-contract=off)
set_target_properties(paper_front_kernels PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../assets/native"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../assets/native"
)
if(MINGW)
    # Windows libraries are loaded by the exact filename in the .gdextension.
    set_target_properties(paper_front_kernels PROPERTIES PREFIX "")
    # Include MinGW's C++/gcc/pthread runtimes so the portable ZIP needs no
    # compiler-runtime DLLs or system-wide runtime installation.
    target_link_options(paper_front_kernels PRIVATE -static -static-libgcc -static-libstdc++)
endif()
