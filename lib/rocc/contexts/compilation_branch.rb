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

require 'rocc/session/logging'

require 'rocc/code_elements/code_element'

require 'rocc/semantic/condition'

require 'rocc/semantic/function'

module Rocc::Contexts

  class CompilationBranch < Rocc::CodeElements::CodeElement

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

    # XXX_R? make @forks private?

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
    attr_reader :pending_tokens, :scope_stack
    
    # See open_token_request and start_collect_macro_tokens
    attr_reader :token_requester

    attr_reader :compilation_context

    ##
    # Should not be called directly. Call
    # CompilationBranch.root_branch or CompilationBranch#fork instead.
    # FIXME? make protected, private?
    #
    # New branch that branches out from +parent+ and is active while
    # the parent's conditions plus the given +branching_condition+
    # apply.
    #
    # +parent+ is the branch the new branch derives from for regular
    # branches, it is the current CompilationContext for the root
    # branch.
    #
    # +master+ is the branch from which to derive the current
    # compilation progress' state information. For a regular fork,
    # +master+ is the same as +parent+, but when creating a branch
    # when joining two child branches of the same parent, master and
    # parent may differ. +nil+ for root branch.
    #
    # +branching_condition+ refers to a +CeCondition+ object for
    # regular branches, it is nil for the initial branch.
    #
    # +adducer+ The CodeElement that caused to fork this branch.
    def initialize(parent, master, branching_condition, adducer)
      super(parent)
      @parent = parent # XXX_R redundant to CodeElement#origin
      @branching_condition = branching_condition
      @adducer = adducer

      @active = true
      @forks = []
      @cached_conditions = nil
      @next_fork_id = 1
      
      if is_root?
        @id = '*'
        @compilation_context = parent
        @pending_tokens = []
        @scope_stack = [ parent.translation_unit ]
        @token_requester = nil
      else
        @id = parent.next_fork_id
        @compilation_context = master.compilation_context
        derive_progress_info(master)
      end

      log.debug{"new cc_branch: #{self} from #{master}, child of #{parent}"}
    end

    def name_dbg
      "CcBr[#{@id}]"
    end

    def derive_progress_info(master)
      @pending_tokens = master.pending_tokens.dup
      @scope_stack = master.scope_stack.dup
      @scope_stack.last = @scope_stack.last.dup if @scope_stack.last.class.name.start_with?('Rocc::Semantic::Temporary::') # XXX_F more efficient test to check for mutable objects
      @token_requester = master.token_requester
    end
    protected :derive_progress_info
    
    ##
    # Is this the main branch directly initiated from the
    # CompilationContext?
    def is_root?
      @parent.is_a?(CompilationContext)
    end

    def self.root_branch(compilation_context)
      # XXX? use compilation_context as adducer only and not as
      # adducer and as parent?
      self.new(compilation_context, nil, Rocc::Semantic::CeUnconditionalCondition.instance, compilation_context)
    end

    #def register(forked_branch)
    #  forked_branch.id = @id + ':' + @next_fork_id.to_s
    #  @next_fork_id += 1
    #  @forks << forked_branch
    #end

    def next_fork_id
      id = @id + ':' + @next_fork_id.to_s
      @next_fork_id += 1
      id
    end

    ##
    # Derive a new branch from this branch that processes the
    # compilation done when +branching_condition+ applies.
    def fork(branching_condition, adducer)
      f = self.class.new(self, self, branching_condition, adducer)
      @forks << f
      log.info{"fork #{f} from #{self} due to #{adducer}"}
      f
    end

    def has_forks?
      not forks.empty?
    end

    def id=(arg)
      raise if @id
      @id = arg
    end
    protected :id=

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
      Rocc::Helpers::String::str_no_lbreak(@pending_tokens.inject("") {|str, tkn| str + tkn.text + tkn.whitespace_after})
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
      case current_scope
      when Rocc::Semantic::Temporary::ArisingSpecification
        current_scope.finalize # FIXME_W set conditions in finalize method
        sym = current_scope.create_symbol
        same = find_symbols(sym)
        if same.empty?
          compilation_context.announce_symbol(sym)
        else
          raise if same.length > 1 # XXX(assert)
          # drop newly created symbol if there is already an according
          # object
          sym = same.first
        end
        spec = current_scope.launch_declaration(sym) # XXX rename ArisingSpecification#finalize

        spec = current_scope.launch_definition(spec) if current_scope.is_definition?
        
        compilation_context.announce_semantic_element(spec)
        spec
        
      when Rocc::Semantic::CeInitializer,
           Rocc::Semantic::CompoundStatement
        current_scope.finalize # FIXME_W set conditions in finalize method
        body = current_scope
        leave_scope
        raise unless current_scope.is_a?(Rocc::Semantic::CeDefinition) # XXX(assert)
        current_scope.body = body
        current_scope.finalize # FIXME_W set conditions in finalize method
        definition = current_scope
        leave_scope
        raise unless current_scope.is_a?(Rocc::Semantic::Temporary::ArisingSpecification) # XXX(assert)
        definition
      else
        #warn scope_stack_trace
        raise "programming error or not yet implemented"
      end
    end

    def leave_scope
      #warn "leave scope: #{"  " * (@scope_stack.count - 1)}< #{scope_name_dbg(@scope_stack.last)}"
      @scope_stack.pop
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

    def scope_name_dbg(scope)
      case scope
      when Rocc::CodeElements::CodeElement, Rocc::Semantic::Temporary::ArisingSpecification
        scope.name_dbg
      else
        scope.inspect
      end
    end
    private :scope_name_dbg

    
    # for debugging
    def scope_stack_trace
      result = "scope_stack of #{name_dbg}:\n"
      @scope_stack.reverse_each do |frame|
        result += "\t#{scope_name_dbg(frame)}\n"
      end
      result
    end

    def declare_symbol(newly_created_symbol)
      log.debug{"#{name_dbg}.declare_symbol: #{newly_created_symbol}"}
      
      overlapping_symbols = find_symbols(
        :identifier => identifier,
        :namespace => symbol_family.namespace,
        #:symbol_family => symbol_family
      )

      overlap_by_conditions = overlapping_symbols.group_by do |s|
        case
        when s.existence_conditions.imply?(newly_created_symbol.existence_conditions)
          :implies
        when newly_created_symbol.existence_conditions.imply?(s.existence_conditions)
          :implied
        else
          :independent
        end
      end

      #raise "conflicting symbols: #{conflicting} and #{identifier}" if conflicting = (overlap_by_conditions[:implies] + overlap_by_conditions[:implied]).find {|s| s != newly_created_symbol}

      symbol = newly_created_symbol

      if not overlap_by_conditions[:implies].empty?
        raise unless overlap_by_conditions[:implied].empty? # XXX(assert)
        raise if overlap_by_conditions[:implies].length > 1 # XXX(assert)
        s = overlap_by_conditions[:implies].first
        raise "conflicting symbols: #{s} and #{symbol}" unless s == symbol
        # drop newly created symbol, use already known symbol instead
        symbol = s
      elsif not overlap_by_conditions[:implied].empty?
        raise unless overlap_by_conditions[:implies].empty? # XXX(assert)
        raise if overlap_by_conditions[:implied].length > 1 # XXX(assert)
        s = overlap_by_conditions[:implied].first
        raise "conflicting symbols: #{s} and #{symbol}" unless s == symbol
        s.existence_conditions = s.existence_conditions.conjunction(symbol.existence_conditions)
        # drop newly created symbol, use already known symbol instead
        symbol = s        
      elsif not overlap_by_conditions[:independent].empty?
        same = overlap_by_conditions[:independent].select {|s| s == symbol }
        raise if same.length > 1 # XXX(assert)
        s = same.first
        s.existence_conditions = s.existence_conditions.conjunction(symbol.existence_conditions)
        # drop newly created symbol, use already known symbol instead
        symbol = s
      end

      compilation_context.announce_symbol(symbol) if symbol.equal?(newly_created_symbol)

      enter_scope(declaration)
      enter_scope(symbol)

      symbol
    end # declare_symbol

    def define_symbol(origin, symbol_family, identifier, definition, hashargs = {})
      symbol = declare_symbol
      symbol.add_definition(definition)
    end

    def find_symbols(criteria)
      compilation_context.find_symbols(criteria)
    end

    #def collect_forks
    #  @forks.each {|f| f.try_join}
    #end

    ##
    # If compilation branches +self+ and +other+ can be merged into a
    # single branch, do so. Joint branch will be the common parent
    # branch if both branches share the same parent branch and
    # conditions of the joint branch are the same as the parent
    # branch's conditions, or a newly created branch otherwise.
    def try_join(other)
      possible = join_possible?(other)
      log.debug{"#{self}.try_join(#{other}) -> #{possible ? 'possible' : 'not possible'}"}
      if possible
        join(other)
      else
        false
      end
    end
    protected :try_join

    # FIXME_R? IS THIS STILL TRUE?! TEST!! When an #else directive
    # exists, it might happen that forks never get to a point where
    # join_poissible?. E.g., assume parent has pending tokens and/or
    # an arising specification on the scope stack and both get
    # resolved in the #if- and the #else-fork. join_possible? will
    # (very likely) not be true until the end of the program and
    # parent branch might fail, though the code is absolutely correct.
    # Resolution(?):
    # - #else branch must always join with the parent branch ??
    # - pursue parent branch with additional conditions as #else branch ??
    def join_possible?(other)
      raise "programming error" unless other.is_active? # XXX(assert)
      raise "programming error" if other.has_forks? # XXX(assert)
      #warn "ADDUCER #{Rocc::Helpers::Debug.dbg_to_s(adducer)} (#{self})"
      #not adducer.active_branch_adducer? and
      not has_forks? and not other.has_forks? and
        @pending_tokens == other.pending_tokens and
        @scope_stack == other.scope_stack and
        @token_requester == other.token_requester
    end
    protected :join_possible?

    def join(other)
      raise "not yet supported" unless @parent == other.parent # XXX(assert)
      raise unless @parent.forks.count >= 2 # XXX(assert)
      
      common_bcond = @branching_condition.disjunction(other.branching_condition)
      joint = self.class.new(@parent, self, common_bcond, [self, other])

      log.info{"join #{self} and #{other} into #{joint}"}
      
      joint
    end
    private :join

    def try_join_forks
      if @forks.length == 1 and
         #not @forks.first.adducer.active_branch_adducer? and
         @branching_condition.equivalent?(@forks.first.branching_condition)
        join_forks
      end
    end
    private :try_join_forks

    def join_forks
      raise "join_fork called, but #{self} still has forks #{@forks}" unless @forks.length == 1 # XXX(assert)
      raise "distinct conditions of branch and last remaining fork: parent <=> #{@branching_condition}, fork <=> #{@forks.first.branching_condition}" unless @branching_condition.equivalent?(@forks.first.branching_condition) # XXX(assert)
      log.info{"join #{@forks.first} into #{self}"}
      derive_progress_info(self)
      @forks = []
      self
    end
    private :join_forks

    # Join as many (active) branches as possible.
    #
    # Returns false if no branches could be joined, true otherwise.
    def consolidate_branches
      if @forks.empty?
        raise "programming error: method should not be invoked on leaf nodes" unless is_root? # XXX(assert)
        return false
      end

      consol_forks = []
      joint_some = false

      has_joint = @forks.first.consolidate_branches if @forks.first.has_forks? and @forks.first.is_active?
      joint_some ||= has_joint

      #warn "FOO"

      final_fork = @forks.inject do |one, another|
        #warn "INJECT ITER #{one}, #{another}"
        
        if one.is_active?
          if another.is_active?
            
            if another.has_forks?
              has_joint = another.consolidate_branches
              joint_some ||= has_joint
            end

            joint = nil
            if another.has_forks?
            #joint = one.try_join(another.first_active_fork) # XXX
            else
              joint = one.try_join(another)
            end
            consol_forks << one unless joint
            joint_some ||= joint
            
            # pass either joint or another to next inject iteration
            joint ? joint : another

          else # another.is_active?

            # should not occure, active branches should be after
            # inactive branches in @forks array ... I think ...
            log.warn{"Unexpected: Inactive #{another} after active #{one}! (rocc developer should have a closer look into this ...)"}
            
            # try to join one with the next in next iteration
            # TODO_R changes order of branches in @forks array
            consol_forks << another
            one

          end
          
        else # one.is_active?

          # try to join another with the next in next iteration
          consol_forks << one
          another

        end
        
      end

      consol_forks << final_fork

      @forks = consol_forks

      has_joint = try_join_forks
      joint_some ||= has_joint
      
      joint_some
    end # def consolidate_branches
    
    
    def finalize
      raise "function shall not be invoked on any non-root branch" unless is_root? # XXX(assert)
      if @forks.empty? and
         @pending_tokens.empty? and
         @scope_stack == [ parent.translation_unit ] and
         @token_requester.nil?
        true
      else
        raise "unexpected end of root branch"
      end
    end

    ###
    ## Mark this compilation branch as dead end. Log according message
    ## if logging level is set accrodingly. If a block is passed to
    ## the method, that block must evaluate to a String object and the
    ## String object will be included in the message being logged.
    #def fail
    #  deactivate
    #  log.warn do
    #    message = yield
    #    "Failed processing branch #{@id}" +
    #      if message
    #        ": #{message}"
    #      else
    #        "."
    #      end
    #  end
    #  log.info "Conditions of failed branch: #{@conditions.dbg_name}"
    #  raise
    #end # def fail

    def is_active?
      @active
    end
    
    ##
    # activate branch
    def activate
      log.debug{"Activate #{self}"}
      @active = true
    end

    ##
    # mark branch as inactive
    def deactivate
      log.debug{"Deactivate #{self}"}
      @active = false
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

    # return array of all active leaf node branches from this branch
    def active_branches
      if is_active?
        if has_forks?
          @forks.map {|f| f.active_branches}.flatten
        else
          [ self ]
        end
      else
        []
      end
    end

  end # class CompilationBranch

end # module Rocc::Contexts
