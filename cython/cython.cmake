# Copyright (C) 2019 LAAS-CNRS, JRL AIST-CNRS, INRIA.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

option(PYTHON_BINDING "Generate Python binding" ON)
if(WIN32)
  set(PYTHON_BINDING_USER_INSTALL_DEFAULT ON)
else()
  set(PYTHON_BINDING_USER_INSTALL_DEFAULT OFF)
endif()
option(PYTHON_BINDING_USER_INSTALL "Install the Python binding in user space" ${PYTHON_BINDING_USER_INSTALL_DEFAULT})
option(PYTHON_BINDING_FORCE_PYTHON2 "Use pip2/python2 instead of pip/python" OFF)
option(PYTHON_BINDING_FORCE_PYTHON3 "Use pip3/python3 instead of pip/python" OFF)
set(PYTHON_BINDING_BUILD_PYTHON2_AND_PYTHON3_DEFAULT OFF)
if(DEFINED PYTHON_DEB_ROOT)
  set(PYTHON_BINDING_BUILD_PYTHON2_AND_PYTHON3_DEFAULT ON)
endif()
option(PYTHON_BINDING_BUILD_PYTHON2_AND_PYTHON3 "Build Python 2 and Python 3 bindings" ${PYTHON_BINDING_BUILD_PYTHON2_AND_PYTHON3_DEFAULT})
if(${PYTHON_BINDING_FORCE_PYTHON2} AND ${PYTHON_BINDING_FORCE_PYTHON3})
  message(FATAL_ERROR "Cannot enforce Python 2 and Python 3 at the same time")
endif()
set(CYTHON_SETUP_IN_PY_LOCATION "${CMAKE_CURRENT_LIST_DIR}/setup.in.py")

# Copy bindings source to build directories and create appropriate target for building, installing and testing
macro(_ADD_CYTHON_BINDINGS_TARGETS PYTHON PIP PACKAGE SOURCES TARGETS WITH_TESTS)
  set(SETUP_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}/${PYTHON}/$<CONFIGURATION>")
  if(DEFINED CMAKE_BUILD_TYPE)
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}/${PYTHON}/${CMAKE_BUILD_TYPE}")
  else()
    foreach(CFG ${CMAKE_CONFIGURATION_TYPES})
      file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}/${PYTHON}/${CFG}")
    endforeach()
  endif()
  file(GENERATE
       OUTPUT "${SETUP_LOCATION}/setup.py"
       INPUT "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}/setup.in.py"
  )
  # Target to build the bindings
  set(TARGET_NAME ${PACKAGE}-${PYTHON}-bindings)
  add_custom_target(${TARGET_NAME} ALL
    COMMAND ${CMAKE_COMMAND} -E chdir "${SETUP_LOCATION}" ${PYTHON} setup.py build_ext --inplace
    COMMENT "Generating local ${PACKAGE} ${PYTHON} bindings"
    DEPENDS ${SOURCES} SOURCES ${SOURCES}
  )
  add_dependencies(${TARGET_NAME} ${TARGETS})
  # Copy sources
  set(I 0)
  foreach(SRC ${SOURCES})
    if(IS_ABSOLUTE ${SRC})
      if(NOT ${SRC} MATCHES "^${CMAKE_CURRENT_BINARY_DIR}")
        MESSAGE(FATAL_ERROR "Source provided to ADD_CYTHON_BINDINGS must have a relative path or an absolute path in CMAKE_CURRENT_BINARY_DIR (${CMAKE_CURRENT_BINARY_DIR})")
      endif()
      file(RELATIVE_PATH REL_SRC "${CMAKE_CURRENT_BINARY_DIR}" "${SRC}")
      set(FILE_IN "${SRC}")
      set(FILE_OUT "${SETUP_LOCATION}/${REL_SRC}")
    else()
      set(FILE_IN "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}")
      set(FILE_OUT "${SETUP_LOCATION}/${SRC}")
    endif()
    add_custom_target(copy-sources-${I}-${TARGET_NAME}
      COMMAND ${CMAKE_COMMAND} -E copy ${FILE_IN} ${FILE_OUT}
      DEPENDS ${FILE_IN}
    )
    add_dependencies(${TARGET_NAME} copy-sources-${I}-${TARGET_NAME})
    math(EXPR I "${I} + 1")
  endforeach()
  # Manual target to force regeneration
  add_custom_target(force-${TARGET_NAME}
    COMMAND ${CMAKE_COMMAND} -E chdir "${SETUP_LOCATION}" ${PYTHON} setup.py build_ext --inplace --force
    COMMENT "Generating local ${PACKAGE} ${PYTHON} bindings (forced)"
  )
  # Tests
  if(${WITH_TESTS} AND NOT ${DISABLE_TESTS})
    if(WIN32)
      set(PATH_SEP ";")
    else()
      set(PATH_SEP ":")
    endif()
    set(EXTRA_LD_PATH "")
    foreach(TGT ${TARGETS})
      set(EXTRA_LD_PATH "$<TARGET_FILE_DIR:${TGT}>${PATH_SEP}${EXTRA_LD_PATH}")
    endforeach()
    add_test(NAME test-${TARGET_NAME}
      COMMAND ${CMAKE_COMMAND} -E env LD_LIBRARY_PATH=${EXTRA_LD_PATH}$ENV{LD_LIBRARY_PATH} ${CMAKE_COMMAND} -E chdir "${SETUP_LOCATION}" ${PYTHON} -c "import nose; nose.run()"
    )
  endif()
  # Install targets
  if(DEFINED PYTHON_DEB_ROOT)
    add_custom_target(install-${TARGET_NAME}
      COMMAND ${CMAKE_COMMAND} -E chdir "${SETUP_LOCATION}" ${PYTHON} setup.py install --root=${PYTHON_DEB_ROOT} --install-layout=deb
      COMMENT "Install ${PACKAGE} ${PYTHON} bindings (Debian layout)"
    )
  else()
    set(PIP_EXTRA_OPTIONS "")
    if(${PYTHON_BINDING_USER_INSTALL})
      set(PIP_EXTRA_OPTIONS "--user")
    endif()
    add_custom_target(install-${TARGET_NAME}
      COMMAND ${CMAKE_COMMAND} -E chdir "${SETUP_LOCATION}" ${PIP} install . ${PIP_EXTRA_OPTIONS} --upgrade
      COMMENT "Install ${PACKAGE} ${PYTHON} bindings"
    )
  endif()
  install(CODE "EXECUTE_PROCESS(COMMAND \"${CMAKE_COMMAND}\" --build \"${CMAKE_BINARY_DIR}\" --config \${CMAKE_INSTALL_CONFIG_NAME} --target install-${TARGET_NAME})")
endmacro()

#.rst:
# .. command:: ADD_CYTHON_BINDINGS(PACKAGE TARGETS targets... [VERSION version] [MODULES modules] [EXPORT_SOURCES sources...] [PRIVATE_SOURCES ...])
#
#   This macro add cython bindings using one or more libraries built by the project.
#
#   :PACKAGE:         Name of the Python package
#
#   :TARGETS:         Name of the targets that the bindings should link to
#
#   :VERSION:         Version of the bindings, defaults to ``PROJECT_VERSION``
#
#   :MODULES:         Python modules built by this macro call. Defaults to ``PACKAGE.PACKAGE``
#
#   :EXPORT_SOURCES:  Sources that will be installed along with the package (typically, public pxd files and __init__.py)
#
#   :PRIVATE_SOURCES: Sources that are needed to built the package but will not be installed
#
#   The macro will generate a setup.py script in
#   ``$CMAKE_CURRENT_BINARY_DIR/$PACKAGE/$PYTHON/$<CONFIGURATION>`` and copy the
#   provided sources in this location. Relative paths are preferred to provide
#   sources but one can use absolute paths if and only if the absolute path
#   starts with ``$CMAKE_CURRENT_BINARY_DIR``
#
macro(ADD_CYTHON_BINDINGS PACKAGE)
  set(options)
  set(oneValueArgs VERSION)
  set(multiValueArgs MODULES TARGETS EXPORT_SOURCES PRIVATE_SOURCES)
  cmake_parse_arguments(CYTHON_BINDINGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )
  if(NOT DEFINED CYTHON_BINDINGS_VERSION)
    set(CYTHON_BINDINGS_VERSION ${PROJECT_VERSION})
  endif()
  if(NOT DEFINED CYTHON_BINDINGS_EXPORT_SOURCES)
    set(CYTHON_BINDINGS_EXPORT_SOURCES)
  endif()
  if(NOT DEFINED CYTHON_BINDINGS_PRIVATE_SOURCES)
    set(CYTHON_BINDINGS_PRIVATE_SOURCES)
  endif()
  if(NOT DEFINED CYTHON_BINDINGS_MODULES)
    set(CYTHON_BINDINGS_MODULES "${PACKAGE}.${PACKAGE}")
  endif()
  if(NOT DEFINED CYTHON_BINDINGS_TARGETS)
    message(FATAL_ERROR "Error in ADD_CYTHON_BINDINGS, bindings should depend on at least one target")
  endif()
  # Setup the basic setup script
  set(CYTHON_BINDINGS_SOURCES)
  list(APPEND CYTHON_BINDINGS_SOURCES ${CYTHON_BINDINGS_EXPORT_SOURCES})
  list(APPEND CYTHON_BINDINGS_SOURCES ${CYTHON_BINDINGS_PRIVATE_SOURCES})
  set(WITH_TESTS False)
  foreach(SRC ${CYTHON_BINDINGS_SOURCES})
    if(${SRC} MATCHES "^tests/")
      set(WITH_TESTS True)
    endif()
  endforeach()
  set(CYTHON_BINDINGS_PACKAGE_NAME ${PACKAGE})
  set(CYTHON_BINDINGS_COMPILE_DEFINITIONS)
  set(CYTHON_BINDINGS_INCLUDE_DIRECTORIES)
  set(CYTHON_BINDINGS_LINK_FLAGS)
  set(CYTHON_BINDINGS_LIBRARIES)
  set(CYTHON_BINDINGS_TARGET_FILES)
  foreach(TGT ${CYTHON_BINDINGS_TARGETS})
    list(APPEND CYTHON_BINDINGS_COMPILE_DEFINITIONS "$<TARGET_PROPERTY:${TGT},COMPILE_DEFINITIONS>")
    list(APPEND CYTHON_BINDINGS_INCLUDE_DIRECTORIES "$<TARGET_PROPERTY:${TGT},INCLUDE_DIRECTORIES>")
    list(APPEND CYTHON_BINDINGS_LINK_FLAGS "$<TARGET_PROPERTY:${TGT},LINK_FLAGS>")
    list(APPEND CYTHON_BINDINGS_LIBRARIES "${TGT}$<$<CONFIG:DEBUG>:@PROJECT_DEBUG_POSTFIX@>")
    list(APPEND CYTHON_BINDINGS_TARGET_FILES "$<TARGET_FILE:${TGT}>")
  endforeach()
  configure_file("${CYTHON_SETUP_IN_PY_LOCATION}" "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}/setup.in.py")
  if(${PYTHON_BINDING_BUILD_PYTHON2_AND_PYTHON3})
    _ADD_CYTHON_BINDINGS_TARGETS("python2" "pip2" ${PACKAGE} "${CYTHON_BINDINGS_SOURCES}" "${CYTHON_BINDINGS_TARGETS}" ${WITH_TESTS})
    _ADD_CYTHON_BINDINGS_TARGETS("python3" "pip3" ${PACKAGE} "${CYTHON_BINDINGS_SOURCES}" "${CYTHON_BINDINGS_TARGETS}" ${WITH_TESTS})
  elseif(${PYTHON_BINDING_FORCE_PYTHON3})
    _ADD_CYTHON_BINDINGS_TARGETS("python3" "pip3" ${PACKAGE} "${CYTHON_BINDINGS_SOURCES}" "${CYTHON_BINDINGS_TARGETS}" ${WITH_TESTS})
  elseif(${PYTHON_BINDING_FORCE_PYTHON2})
    _ADD_CYTHON_BINDINGS_TARGETS("python2" "pip2" ${PACKAGE} "${CYTHON_BINDINGS_SOURCES}" "${CYTHON_BINDINGS_TARGETS}" ${WITH_TESTS})
  else()
    _ADD_CYTHON_BINDINGS_TARGETS("python" "pip" ${PACKAGE} "${CYTHON_BINDINGS_SOURCES}" "${CYTHON_BINDINGS_TARGETS}" ${WITH_TESTS})
  endif()
endmacro()