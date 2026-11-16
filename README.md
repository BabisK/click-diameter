click-diameter
==============

[![Build and test](https://github.com/BabisK/click-diameter/actions/workflows/build-and-test.yml/badge.svg?branch=master)](https://github.com/BabisK/click-diameter/actions/workflows/build-and-test.yml)

Diameter package for click router

LAYOUT
======

configure.ac, Makefile.in   build entry points (autoconf, configure and make run here)
src/                        element sources: one .cc/.hh pair per element, plus diameter.hh

INSTALL
=======

autoconf
./configure (for more options --help)
make
make install