# -*- coding: utf-8 -*-

# Copyright (C) 2014-2015  Thilo Fischer.
# Software is free for non-commercial and most commercial use. Integration into commercial applications may require according licensing. See LICENSE.txt for details.

module Rocc::CodeElements::FileRepresented

  ##
  # Represents translation units. A translation unit usually
  # corresponds to an object file being created during compilation.
  class CeTranslationUnit < CodeElement

    attr_reader :include_files

    def initialize(main_file)
      super(main_file)
      @include_files = []
    end

    alias main_file origin

    def add_include_file(file)
      @include_files << file
    end

    def name
      main_file.basename
    end

    
    def symbols(filter = nil)
      # TODO Take filter into account.
      # TODO Make filter an optional block and use select method?
      unless @symbols and up_to_date?
        @symbols = expand
      end
      @symbols
    end
    
    ##
    # Check if files of this translation unit changed on disk.
    #
    # Check based on file modification timestamp and checksum, or
    # based on file modification timestamp only if +mod_time_only+ is
    # +true+.
    def up_to_date?(mod_time_only = false)
      return false unless main_file.up_to_date?(mod_time_only)
      not @include_files.find {|incfile| not incfile.up_to_date?(mod_time_only) }
    end

  end # class CeTranslationUnit

end # module Rocc::CodeElements::FileRepresented