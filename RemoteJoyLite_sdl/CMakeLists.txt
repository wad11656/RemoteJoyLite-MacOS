cmake_minimum_required(VERSION 3.20)

project(RemoteJoyLite-cross LANGUAGES C CXX)

find_package(SDL3 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBUSB REQUIRED libusb-1.0)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")

set(SRC_FILES
  src/main.c
)

if(APPLE)
  enable_language(OBJCXX)
  list(APPEND SRC_FILES
    macos/RemoteJoyLiteMac.mm
  )
endif()

add_executable(${PROJECT_NAME}
  ${SRC_FILES}
)

target_include_directories(${PROJECT_NAME} PRIVATE ${LIBUSB_INCLUDE_DIRS})
target_link_directories(${PROJECT_NAME} PRIVATE ${LIBUSB_LIBRARY_DIRS})
target_link_libraries(${PROJECT_NAME} SDL3::SDL3 ${LIBUSB_LIBRARIES})
target_include_directories(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/..")

if(APPLE)
  find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
  find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
  find_library(AVFOUNDATION_FRAMEWORK AVFoundation REQUIRED)
  find_library(COREMEDIA_FRAMEWORK CoreMedia REQUIRED)
  find_library(COREVIDEO_FRAMEWORK CoreVideo REQUIRED)
  find_library(SCREENCAPTUREKIT_FRAMEWORK ScreenCaptureKit REQUIRED)
  target_link_libraries(${PROJECT_NAME}
    "${COCOA_FRAMEWORK}"
    "${FOUNDATION_FRAMEWORK}"
    "${AVFOUNDATION_FRAMEWORK}"
    "${COREMEDIA_FRAMEWORK}"
    "${COREVIDEO_FRAMEWORK}"
    "${SCREENCAPTUREKIT_FRAMEWORK}"
  )
endif()
