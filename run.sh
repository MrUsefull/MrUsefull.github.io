#!/bin/bash

set -xeu

npm install
npx pagefind --site public
hugo serve -D
