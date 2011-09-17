# Copyright (c) 2005 Trevor Squires
# Released under the MIT License.  See the LICENSE file for more details.

module ActiveRecord
  module Acts 
    module Enumerated 
      def self.append_features(base)
        super        
        base.extend(MacroMethods)              
      end
      
      module MacroMethods          
        def acts_as_enumerated(options = {})
          valid_keys = [:conditions, :order, :on_lookup_failure, :name_column]
          options.assert_valid_keys(*valid_keys)
          
          valid_keys.each do |key|   
            write_inheritable_attribute("acts_enumerated_#{key.to_s}".to_sym, options[key]) if options.has_key? key
          end
          
          name_column = if options.has_key?(:name_column) then
                          options[:name_column].to_s.to_sym
                        else
                          :name
                        end
          write_inheritable_attribute(:acts_enumerated_name_column, name_column)
          
          unless self.is_a? ActiveRecord::Acts::Enumerated::ClassMethods
            extend ActiveRecord::Acts::Enumerated::ClassMethods
            
            class_eval do
              include ActiveRecord::Acts::Enumerated::InstanceMethods
              
              before_save :enumeration_model_update
              before_destroy :enumeration_model_update
              validates name_column, :presence => true, :uniqueness => true
              
              define_method :name do
                read_attribute( name_column )
              end
            end
          end
        end
      end
      
      module ClassMethods  
        attr_accessor :enumeration_model_updates_permitted
        
        def all
          return @all if @all
          @all = find(:all, 
                      :conditions => read_inheritable_attribute(:acts_enumerated_conditions),
                      :order => read_inheritable_attribute(:acts_enumerated_order)
                      ).collect{|val| val.freeze}.freeze
        end

        def [](arg)
          case arg
          when Symbol
            return_val = lookup_name(arg.id2name) and return return_val
          when String
            return_val = lookup_name(arg) and return return_val
          when Fixnum
            return_val = lookup_id(arg) and return return_val
          when nil
            return_val = nil
          else
            raise TypeError, "#{self.name}[]: argument should be a String, Symbol or Fixnum but got a: #{arg.class.name}"            
          end
          self.send((read_inheritable_attribute(:acts_enumerated_on_lookup_failure) || :enforce_none), arg)
        end

        def lookup_id(arg)
          all_by_id[arg]
        end

        def lookup_name(arg)
          all_by_name[arg]
        end
                                   
        def include?(arg)
          case arg
          when Symbol
            !lookup_name(arg.id2name).nil?
          when String
            !lookup_name(arg).nil?
          when Fixnum
            !lookup_id(arg).nil?
          when self
            possible_match = lookup_id(arg.id) 
            !possible_match.nil? && possible_match == arg
          else
            false
          end
        end

        # NOTE: purging the cache is sort of pointless because
        # of the per-process rails model.  
        # By default this blows up noisily just in case you try to be more 
        # clever than rails allows.  
        # For those times (like in Migrations) when you really do want to 
        # alter the records you can silence the carping by setting
        # enumeration_model_updates_permitted to true.
        def purge_enumerations_cache
          unless self.enumeration_model_updates_permitted
            raise "#{self.name}: cache purging disabled for your protection"
          end
          @all = @all_by_name = @all_by_id = nil
        end

        def name_column
          @name_column ||= read_inheritable_attribute( :acts_enumerated_name_column )
        end

        private 
        
        def all_by_id 
          return @all_by_id if @all_by_id
          @all_by_id = all.inject({}) { |memo, item| memo[item.id] = item; memo }.freeze
        end
        
        def all_by_name
          return @all_by_name if @all_by_name
          begin
            @all_by_name = all.inject({}) { |memo, item| memo[item.name] = item; memo }.freeze
          rescue NoMethodError => err
            if err.name == name_column
              raise TypeError, "#{self.name}: you need to define a '#{name_column}' column in the table '#{table_name}'"
            end
            raise
          end            
        end   
        
        def enforce_none(arg)
          nil
        end

        def enforce_strict(arg)
          raise_record_not_found(arg)
        end

        def enforce_strict_literals(arg)
          raise_record_not_found(arg) if (Fixnum === arg) || (Symbol === arg)
          nil
        end

        def enforce_strict_ids(arg)
          raise_record_not_found(arg) if Fixnum === arg
          nil
        end

        def enforce_strict_symbols(arg)
          raise_record_not_found(arg) if Symbol === arg
          nil
        end

        def raise_record_not_found(arg)
          raise ActiveRecord::RecordNotFound, "Couldn't find a #{self.name} identified by (#{arg.inspect})"
        end
        
      end

      module InstanceMethods
        def ===(arg)
          case arg
          when nil
            false
          when Symbol, String, Fixnum
            return self == self.class[arg]
          when Array
            return self.in?(*arg)
          else
            super
          end
        end
        
        alias_method :like?, :===
        
        def in?(*list)
          for item in list
            self === item and return true
          end
          false
        end

        def name_sym
          self.name.to_sym
        end

        private

        # NOTE: updating the models that back an acts_as_enumerated is 
        # rather dangerous because of rails' per-process model.
        # The cached values could get out of synch between processes
        # and rather than completely disallow changes I make you jump 
        # through an extra hoop just in case you're defining your enumeration 
        # values in Migrations.  I.e. set enumeration_model_updates_permitted = true
        def enumeration_model_update
          if self.class.enumeration_model_updates_permitted    
            self.class.purge_enumerations_cache
            true
          else
            # Ugh.  This just seems hack-ish.  I wonder if there's a better way.
            self.errors.add(self.class.name_column, "changes to acts_as_enumeration model instances are not permitted")
            false
          end
        end
      end
    end
  end
end
        
