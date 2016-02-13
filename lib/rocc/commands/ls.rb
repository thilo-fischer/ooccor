# -*- coding: utf-8 -*-

# Copyright (c) 2014-2016  Thilo Fischer.
#
# This file is part of rocc.
#
# rocc is free software with a multi-license approach: you can
# redistribute it and/or modify it as if it was under the terms of the
# GNU General Public License as long as the things you publish to
# satisfy the GPL's copyleft still can be integrated into the rocc
# project's main codebase without restricting the multi-license
# approach. See LICENSE.txt from the top-level directory for details.

require 'rocc/ui/textual_representation'

module Rocc::Commands

  class Ls < Command

    @name = 'ls'
    @description = 'List objects.'
    
    def self.option_parser(options)

      OptionParser.new do |opts|      

        opts.banner = "Usage: #{@name} [options] [object]..."
        
        opts.on(
          "-t type",
          "--type",
          %w[file symbol identifier macro function variable type
             tag struct union enum label],
          "list only objects of a certain type"
        ) do |arg|
          if options.key?(:type) then
            options[:type] = [arg]
          else
            options[:type] << arg
          end
        end

        opts.on(
          "--literal [type]",
          %w[string char integer float],
          "list literals of specific type"
        ) do |arg|
          if options.key?(:literal) then
            options[:literal] = [arg]
          else
            options[:literal] << arg
          end
        end

        opts.on(
          "--comment [type]",
          %w[block line],
          "list comments"
        ) do |arg|
          if options.key?(:comment) then
            options[:comment] = [arg]
          else
            options[:comment] << arg
          end
        end

        opts.on(
          "-f criteria",
          "--filter",
          "list only objects matching the given filter criteria."
          #Multiple filter criteria may be defined by repeating this flag multiple times.
        ) do |arg|
          if options.key?(:filter) then
            options[:filter] = [arg]
          else
            options[:filter] << arg
          end
        end

        opts.on(
          "-l",
          "--long",
          "long listing format"
        ) do |arg|
          options[:format] = :long
        end

        opts.on(
          "--format format_string",
          "list symbols using the given format string"
        ) do |arg|
          options[:format] = arg
        end

        #opts.on("-F",
        #        "--classify",
        #        "append indicator representing it's type to objects") do |arg|
        #  options[:one_per_line] = true
        #end

        #opts.on("-1",
        #        "--one-per-line",
        #        "list one object per line") do |arg|
        #  options[:one_per_line] = true
        #end

        opts.on(
          "--each",
          "list each declaration or definition of a symbol, not just one per symbol"
        ) do |arg|
          options[:each] = true
        end

        opts.on(
          "--assume condition",
          "for preprocessor conditionals, assume condition is true"
        ) do |arg|
          list = options[:assume] ||= []
          list << arg
        end

        opts.on(
          "--assume-def macro",
          "for preprocessor conditionals, assume a macro with the given name is defined"
        ) do |arg|
          list = options[:assume] ||= []
          list << "defined(#{arg})"
        end

        

      end
      
    end # option_parser


    def self.run(applctx, args, options)
      
      if applctx.cursor == Dir then
        puts `ls #{args.join(" ")}`
      elsif args.empty?
        #warn "cursor: #{applctx.cursor}"
        #warn "symbols: #{applctx.cursor.find_symbols}"
        symbol_formatter = Rocc::Ui::SymbolFormatter.compile
        applctx.cursor.find_symbols(:origin => applctx.cursor).each do |s|
          puts symbol_formatter.format(s)
        end
      else
        args.each { |o| o.list(STDOUT, options) }
      end

    end # run

  end # class Ls


  Ls.register

end # module Rocc::Commands
