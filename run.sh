#!/bin/bash

set -xeu

npx -y pagefind --site public
hugo serve -D
