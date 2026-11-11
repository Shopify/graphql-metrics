# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require 'graphql/batch'

require "minitest/autorun"
require "minitest/focus"
require 'mocha/minitest'

require 'pry'
require 'diffy'
require 'hashdiff'

require 'graphql'
require "graphql/metrics"
require 'fakeredis'
