# -*- coding: utf-8 -*-

# Copyright (C) 2014  Thilo Fischer.
# Free software licensed under GPL v3. See LICENSE.txt for details.

module Ooccor::CodeObjects

  require 'ooccor/code_objects/code_object'
  require 'ooccor/code_objects/file'

  class CoProgram < CodeObject

    def initialize
      @objects = {}
    end

    def register(o)
      if @objects.key?(o.class) then
        @objects[o.class] << o
      else
        @objects[o.class] = [ o ]
      end
    end

    def base_dir
      return nil if @objects[CoFile].empty?

      base_dir = @objects[CoFile].map do |f|
        #      File.dirname(f.abs_path).split('/')
        f.abs_path.split('/')[0..-2]
      end.inject do |base, new|
        #      for i in [0 .. base.length-1] do
        #        return base[0..i-1] if base[i] != new[i]
        #      end
        base.each_with_index do |dir, i|
          return base[0..i-1] if dir != new[i]
        end
        return base
      end
      
      File.join(base_dir)
    end # base_dir

    def to_s
      '*'
    end

    def get_all
      #    dbg @objects.inspect
      @objects.values.flatten(1)
    end

    alias content get_all

    def get_all_of_class(c)
      raise unless c < CodeObject
      @objects[c]
    end

    def get_all_of_kind(baseclass)
      raise unless baseclass < CodeObject
      result = []
      @objects.each do |cls, objs| 
        result += objs if cls < baseclass
      end
      result
    end

    private

    def validate_origin(origin)
      # Program is root node => origin == nil
      raise if origin != nil
      nil
    end

  end # class CoProgram

end # module Ooccor::CodeObjects