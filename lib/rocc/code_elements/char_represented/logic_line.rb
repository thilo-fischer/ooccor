# -*- coding: utf-8 -*-

# Copyright (C) 2014-2015  Thilo Fischer.
# Software is free for non-commercial and most commercial use. Integration into commercial applications may require according licensing. See LICENSE.txt for details.

module Rocc::CodeObjects

  require 'rocc/code_objects/code_object'

  # forward declarations
  class CoFile < CodeObject; end

  require 'rocc/code_objects/tokens/tokens'
  
  
  class CoLogicLine < CodeObject
    attr_reader :indentation

    def initialize(origin)
      super(origin)
      @tokens = nil
      @indentation = nil
    end # initialize

    def text
      if origin.class == Range
        raise "TODO"
#        # merge physical lines
#        if env.remainders.include? self.class
#          text = env.remainders[self.class].map {|ln| ln.text.sub(/\\$/,"")}.join + text
#          origin = env.remainders[self.class][0] .. self
#          env.remainders.delete self.class
#        end
      else
        origin.text
      end
    end

    def announce
      # Don't want to register lines, they can be referenced from the content of ... are they? (fixme)
      nil
    end

    def pursue(lineread_context)
      comment_context = lineread_context.comment_context
      tokenize(comment_context).map {|t| t.pursue(comment_context.compilation_context)}
    end

    def tokens
      raise "#{to_s} has not yet been tokenized." unless @tokens
      @tokens
    end

    alias content tokens

    private

    # TODO move more code from here to TokenizationContext, rename TokenizationContext => Tokenizer
    def tokenize(comment_context)

      tokenization_context = TokenizationContext.new(comment_context, self)
    
      if tokenization_context.in_multiline_comment?
        # handle ongoing multi line comment
        Tokens::TknMultiLineBlockComment.pick!(tokenization_context)
        tokenization_context.leave_multiline_comment unless tokenization_context.recent_token.complete? # FIXME leave multiline comment when parsing `*/'
      else
        # remove leading whitespace
        @indentation = tokenization_context.lstrip
      end
      
      tokenization_context.pick_pp_directives

      until tokenization_context.finished? do
        unless Tokens::CoToken::PICKING_ORDER.find {|c| c.pick!(tokenization_context)}
          raise "Could not dertermine next token in `#{remainder}'"
        end
      end

      # FIXME enter multiline comment when parsing `/*'
      if tokenization_context.recent_token and
        tokenization_context.recent_token.class.is_a? Tokens::TknMultiLineBlockComment and
        not tokenization_context.recent_token.complete?
        tokenization_context.announce_multiline_comment(tokenization_context.recent_token)
      end
        
     tokenization_context.terminate

     @tokens

    end # tokenize

  end # class CoLogicLine

end # module Rocc::CodeObjects
