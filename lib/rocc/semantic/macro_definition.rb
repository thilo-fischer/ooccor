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

require 'rocc/semantic/specification.rb'

module Rocc::Semantic

  ##
  # Represents the specification of a macro.
  class CeMacroDefinition < CeSpecification

    ##
    # +origin+ of a +MacroDefinition+ shall be the CeCoPpDefine object
    # representing the preprocessor directive that defines it.
    def initialize(origin)
      super(origin)
    end

    alias define_directive origin

    ## same result as CodeElement#existence_conditions
    #def existence_conditions
    #  define_directive.existence_conditions
    #end
    
    def name_dbg
      "#MDef[#{origin.identifier}]"
    end

  end # class CeMacroDefinition

end # module Rocc::Semantic
