#!/bin/sh

clear
echo "Trying to clean & compile the Elixir application"
mix clean
mix deps.get
mix deps.compile
mix compile
