# -*- coding: utf-8 -*-

# Copyright (C) 2014-2016  Thilo Fischer.
#
# This file is part of rocc.
#
# rocc is free software with a multi-license approach: you can
# redistribute it and/or modify it as if it was under the terms of the
# GNU General Public License as long as the things you publish to
# satisfy the GPL's copyleft still can be integrated into the rocc
# project's main codebase without restricting the multi-license
# approach. See LICENSE.txt from the top-level directory for details.

require 'rocc/session/logging'

require 'rocc/code_elements/code_element'

require 'rocc/semantic/symbol_index'
require 'rocc/semantic/condition'

require 'rocc/semantic/function'

module Rocc::Contexts

  class CompilationBranch

    extend  Rocc::Session::LogClientClassMixin
    include Rocc::Session::LogClientInstanceMixin

    ##
    # Data members wrt managing a tree of compilation branches.
    #
    # +parent+ The branch this branch was forked from.
    #
    # +branching_condition+ The (preprocessor) codition(s) that
    # apply to this branch in addition to the conditions that apply
    # to its parent branch.
    #
    # +forks+ Array of branches forked from this branch.
    #
    # +id+ String identifying this branch, listing its ancestry.
    #
    # +adducer+ The CodeElement that caused to fork this branch.
    attr_reader :parent, :branching_condition, :forks, :id, :adducer

    ##
    # Data members wrt interpreting the tokens within a specific
    # branch.
    # 
    # +pending_tokens+ Array of successive tokens which could not yet
    # be associated with specific semantics and must be taken into
    # account and will influence the semantics of a token to be parsed
    # soon.
    #
    # +scope_stack+ Stack of the semantic contexts that could be
    # identified and within which the interpretation of the following
    # tokens must be done.
    #
    # +most_recent_scope+ The scope most recently taken from the
    # scope_stack (if any, nil otherwise).
    attr_reader :pending_tokens, :scope_stack, :most_recent_scope, :ppcond_stack

    # See open_token_request and start_collect_macro_tokens
    attr_reader :token_requester
      
    ##
    # Should not be called directly. Call
    # CompilationBranch.root_branch or CompilationBranch#fork instead.
    # FIXME? make protected, private?
    #
    # New branch that branches out from +parent+ and is active when
    # the parent's conditions plus the given +branching_condition+
    # apply.
    #
    # +parent+ is the branch the new branch derives from for regular
    # branches, it is the current CompilationContext for the root
    # branch.
    #
    # +branching_condition+ refers to a +CeCondition+ object for
    # regular branches, it is nil for the initial branch.
    #
    # +adducer+ The CodeElement that caused to fork this branch.
    def initialize(parent, branching_condition, adducer)
      @parent = parent
      @branching_condition = branching_condition
      @adducer = adducer

      if is_root?
        @id = '*'
        @pending_tokens = []
        @scope_stack = [ parent.translation_unit ]
        @most_recent_scope = nil
        @ppcond_stack = []
        @token_requester = nil
      else
        @id = nil # will be set after registration at parent
        @pending_tokens = parent.pending_tokens.dup
        @scope_stack = parent.scope_stack.dup
        @most_recent_scope = parent.most_recent_scope
        @ppcond_stack = parent.ppcond_stack.dup
        @token_requester = parent.token_requester
      end

      @active = true
      @symbol_idx = Rocc::Semantic::SymbolIndex.new
      @forks = []
      @cached_conditions = nil
    end

    ##
    # Is this the main branch directly initiated from the
    # CompilationContext?
    def is_root?
      @parent.is_a?(CompilationContext)
    end

    def self.root_branch(compilation_context)
      # XXX? use compilation_context as adducer instead of as parent?
      self.new(compilation_context, Rocc::Semantic::CeEmptyCondition.instance, nil)
    end

    ##
    # Derive a new branch from this branch that processes the
    # compilation done when +branching_condition+ applies.
    def fork(branching_condition, adducer)
      f = self.class.new(self, branching_condition, adducer)
      f.id = register_fork(f)
      #warn "XXXXXXXX #{name_dbg}.fork(#{branching_condition.inspect}, #{adducer.name_dbg}) => #{f.name_dbg}"
      f      
    end

    def has_forks?
      not forks.empty?
    end

    private
    def register_fork(fork)
      fork_id = @id + '-' + @forks.count.to_s
      @forks << fork
      fork_id
    end

    protected
    def id=(arg)
      raise if @id
      @id = arg
    end

    public
    ##
    # Conditions that must apply to make those preprocessor
    # conditionals' branches active that correspond to this branch.
    def conditions
      if is_root?
        @branching_condition
      else
        #warn "#{name_dbg}.conditions, @parent.conditions: #{@parent.conditions}"
        @cached_conditions ||= @parent.conditions.conjunction(@branching_condition)
      end
    end
    
    ##
    # Add one more tokens to the list of successively parsed tokens
    # for which no semantics could be assigned yet.
    def push_pending(token)
      if token.is_a? Array
        @pending_tokens += token
      else
        @pending_tokens << token
      end
    end

    ##
    # Clear the list of successively parsed tokens
    # for which no semantics could be assigned yet.
    def clear_pending
      @pending_tokens = []
    end

    ##
    # Any recently parsed tokens for which no semantics could be
    # assigned yet?
    def has_pending?
      not @pending_tokens.empty?
    end

    ##
    # For debugging and user messages: Textual representation of the
    # recently parsed tokens for which no semantics could be assigned
    # yet.
    def pending_to_s
      Rocc::Helpers::String::no_lbreak(@pending_tokens.inject("") {|str, tkn| str + tkn.text + tkn.whitespace_after})
    end

    def enter_scope(scope)
      #warn "enter scope: #{"  " * (@scope_stack.count - 0)}> #{scope_name_dbg(scope)}"
      raise if scope == nil
      @scope_stack << scope
    end

    def current_scope
      @scope_stack.last
    end

    ##
    # Return the object marking a scope somewhere deeper in the scope
    # stack. +depth+ devines how many levels to descend.
    #
    # +surrounding_scope(1)+ (which is the default if no +depth+
    # argement is given) returns the scope directly enclosing
    # +current_scope+. +surrounding_scope(0)+ is equivallent to
    # +current_scope+.
    # 
    def surrounding_scope(depth = 1)
      raise "invalid argument: #{depth}" if depth < 0
      depth = -1 - depth
      @scope_stack[depth]
    end

    def finish_current_scope
      #warn "finish_current_scope -> #{scope_stack_trace}"
      raise unless current_scope.is_a? Rocc::Semantic::Temporary::ArisingSpecification
      symbol = current_scope.finalize(self)
      leave_scope
      symbol
    end

    def leave_scope
      #warn "leave scope: #{"  " * (@scope_stack.count - 1)}< #{scope_name_dbg(@scope_stack.last)}"
      @most_recent_scope = @scope_stack.pop
    end

    def find_scope(symbol_family)
      idx = nil
      case symbol_family
      when Class
        idx = @scope_stack.rindex {|s| s.is_a?(symbol_family)}
      when Array
        idx = @scope_stack.rindex do |s|
          symbol_family.find {|f| s.is_a?(f)}
        end
      else
        raise "invalid argument"
      end
      @scope_stack[idx] if idx
    end

    ##
    # find the closest scope (i.e. the surrounding scope with the
    # highest position in the scope stack) that can be the origin of a
    # symbol
    def closest_symbol_origin_scope
      result = find_scope([Rocc::CodeElements::FileRepresented::CeTranslationUnit, Rocc::Semantic::CompoundStatement])
    end

    private
    def scope_name_dbg(scope)
      case scope
      when Rocc::CodeElements::CodeElement, Rocc::Semantic::Temporary::ArisingSpecification
        scope.name_dbg
      else
        scope.inspect
      end
    end

    public
    
    # for debugging
    def scope_stack_trace
      result = "scope_stack of #{name_dbg}:\n"
      @scope_stack.reverse_each do |frame|
        result += "\t#{scope_name_dbg(frame)}\n"
      end
      result
    end

    def announce_symbols(other_symbol_idx)
      @symbol_idx.announce_symbols(other_symbol_idx)
    end
    
    # FIXME_R clarify coherence of announce_created_symbol and announce_symbol
    # FIXME_R? merge announce_created_symbol and announce_symbol?
    def announce_created_symbol(symbol)
      @symbol_idx.announce_symbol(symbol)
    end

    def announce_symbol(origin, symbol_family, identifier, hashargs = {})

      log.debug{"#{name_dbg}.announce_symbol: #{origin}, #{symbol_family}, #{identifier}, #{hashargs.inspect}"}
      #warn caller
      #warn scope_stack_trace

      linkage = nil
      
      if find_scope(Rocc::Semantic::CeFunction)
        linkage = :none
      elsif hashargs.key?(:storage_class)
        case hashargs[:storage_class]
        when :typedef
          raise "not yet supported" # FIXME
        when :static
          linkage = :intern
        when :extern
          linkage = :extern # XXX what about function local symbols declared with storage class specifier extern ?
        end
      else
        linkage = symbol_family.default_linkage # XXX necessary to query symbol_familiy or is it always :extern anyways?
      end # find_scope(Rocc::Semantic::CeFunction)

      raise "programming error" unless linkage
      hashargs[:linkage] = linkage

      symbols = find_symbols(:identifier => identifier, :symbol_family => symbol_family)

      if symbols.empty?

        # symbol detected for the first time
        symbol = symbol_family.new(origin, identifier, hashargs)
        @symbol_idx.announce_symbol(symbol)

      else
        
        raise if symbols.count > 1 # XXX
        symbol = symbols.first

        # FIXME compare linkage, storage_class, type_qualifiers and type_specifiers of the annonced and the indexed symbol => must be compatible
        raise "inconsistend declarations" if false # symbol.type_qualifiers != type_qualifiers or symbol.type_specifiers != type_specifiers

      end # symbols.empty?

      symbol
    end # announce_symbol

    def find_symbols(criteria)
      result = []
      c = criteria.clone
      result += @symbol_idx.find_symbols(c)
      c = criteria.clone
      result += @parent.find_symbols(c) if not is_root?
      result
    end

    #def collect_forks
    #  @forks.each {|f| f.try_join}
    #end

    def try_join
      if join_possible? 
        join
      end
    end

    # FIXME_R when an #else directive exists, it might happen that forks never get to a point where join_poissible?. E.g., assume parent has pending tokens and/or an arising specification on the scope stack and both get resolved in the #if- and the #else-fork. join_possible? will (very likely) not be true until the end of the program and parent branch might fail, though the code is absolutely correct. Resolution(?):
    # - #else branch must always join with the parent branch ??
    # - pursue parent branch with additional conditions as #else branch ??
    def join_possible?
      return nil if is_root?
      return false unless parent.is_active?
      @ppcond_stack == parent.ppcond_stack and
        @pending_tokens == parent.pending_tokens and
        @scope_stack == parent.scope_stack and
        @most_recent_scope == parent.most_recent_scope and
        @token_requester == parent.token_requester and
    end

    def join
      @parent.announce_symbols(@symbol_idx)
      deactivate
      @parent
    end
    private :join
    
    def terminate
      if has_pending?
        fail{"Branch terminated while still having pending tokens."}
        log.debug{"Pending tokens: #{pending_to_s}"}
        raise
      end
      @forks.each {|c| c.terminate }
      if is_root?
        @parent.announce_symbols(@symbol_idx)
      else        
        raise unless join_possible?
        join
      end
    end

    ##
    # Mark this compilation branch as dead end. Log according message
    # if logging level is set accrodingly. If a block is passed to
    # the method, that block must evaluate to a String object and the
    # String object will be included in the message being logged.
    def fail
      deactivate
      log.warn do
        message = yield
        "Failed processing branch #{@id}" +
          if message
            ": #{message}"
          else
            "."
          end
      end
      log.info "Conditions of failed branch: #{@conditions.dbg_name}"
      raise
    end # def fail

    def is_active?
      @active
    end

    def activate(branch = self)      
      #warn "~~~ #{branch.name_dbg}.activate(#{branch.name_dbg}) <- #{caller[0..1].map {|c| c.sub(/^.*\//, '')}}"
      @active = true if branch == self
      if is_root?
        parent.activate_branch(branch)
      else
        parent.activate(branch)
      end
    end
      
    def deactivate(branch = self)
      #warn "~~~ #{branch.name_dbg}.deactivate(#{branch.name_dbg}) <- #{caller[0..1].map {|c| c.sub(/^.*\//, '')}}"
      @active = false if branch == self
      if is_root?
        parent.deactivate_branch(branch)
      else
        parent.deactivate(branch)
      end
    end

    ##
    # Redirect all tokens to code_object instead of invoking
    # pursue_branch on the token until invokation of
    # close_token_request. Logic to achive redirection is implemented
    # in CeToken.pursue.
    def open_token_request(code_object)
      @token_requester = code_object
    end

    # See open_token_request
    def close_token_request
      @token_requester = nil
    end

    # See open_token_request
    def has_token_request?
      @token_requester
    end

    def announce_pp_branch(ppcond_directive)
      raise "programming error :( -> #{ppcond_directive.name_dbg}, associated_cond_dirs: #{ppcond_directive.associated_cond_dirs}" unless ppcond_directive.associated_cond_dirs.include?(ppcond_directive) # XXX defensive programming, substitute with according unit test

      case ppcond_directive
      when Rocc::CodeElements::CharRepresented::CeCoPpCondEndif,
           Rocc::CodeElements::CharRepresented::CeCoPpCondElif,
           Rocc::CodeElements::CharRepresented::CeCoPpCondElse
        # FIXME smells
        if adducer == ppcond_directive.associated_cond_dirs[-2]
          # announce_pp_branch called on branch that was opened to process the previous conditional pp directive
          deactivate
          parent.activate
          parent.announce_pp_branch(ppcond_directive)
        end

        prev = @ppcond_stack.pop
        raise "programming error" unless prev.associated_cond_dirs == ppcond_directive.associated_cond_dirs # XXX defensive programming, substitute with according unit test

        # FIXME smells
        if adducer != ppcond_directive.associated_cond_dirs[-2]
          # announce_pp_branch called on parent branch
          if ppcond_directive.is_a? Rocc::CodeElements::CharRepresented::CeCoPpCondEndif
            forks.each do |f|
              unless f.try_join
                f.activate
              end
            end
          end
        end        

      end
      
      case ppcond_directive
      when Rocc::CodeElements::CharRepresented::CeCoPpCondIf,
           Rocc::CodeElements::CharRepresented::CeCoPpCondElif,
           Rocc::CodeElements::CharRepresented::CeCoPpCondElse
        @ppcond_stack << ppcond_directive
        deactivate
        #warn "#{name_dbg}.announce_pp_branch -> #{conditions.complement(ppcond_directive.collected_conditions)}"
        f = fork(conditions.complement(ppcond_directive.collected_conditions), ppcond_directive)
        f.activate
      end
      
    end # def announce_pp_branch
    
    def name_dbg
      "CcBr[#{@id}]"
    end
    
  end # class CompilationBranch

end # module Rocc
