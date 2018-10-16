# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require 'active_support'
require 'graphql/batch'

require "minitest/autorun"
require "minitest/focus"
require 'mocha/minitest'

require 'pry'
require 'ostruct'
require 'diffy'

require "graphql_metrics"
require 'graphql'
require 'fakeredis'
