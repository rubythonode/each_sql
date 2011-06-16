# encoding: UTF-8
# Junegunn Choi (junegunn.c@gmail.com)

# Enumerable EachSQL object.
class EachSQL
	include Enumerable

	def initialize input, options
		raise NotImplementedError.new if options.nil?
		# immutables
		@org_input = input
		@options = options
		@blocks = @options[:blocks]
		@nblocks = @options[:nesting_blocks]
		@all_blocks = @blocks.merge @nblocks
	end

	def each
		# Phase 1: comment out input
		@input = @org_input.dup
		@input_c = zero_out @org_input

		return nil if @input.nil? || @input.empty?

		@delimiter = @options[:delimiter]

		while @input && @input.length > 0
			# Extract a statement
			statement = next_statement

			# When a non-empty statement is found
			statement = @options[:strip_delimiter].call self, statement if @options[:strip_delimiter]
			if statement.length > 0
				# Apply replacements
				@options[:replace].each do |k, v|
					statement.gsub!(k, v)
				end
				statement.strip!

				# Process callbacks
				@options[:callbacks].each do |pattern, callback|
					md = statement.match pattern
					callback.call self, statement, md if md
				end

				# Ignore
				if (@options[:ignore] || []).all? { |ipat| statement !~ ipat }
					yield statement
					@prev_statement = statement
				end
			end
		end
		nil
	end

	attr_accessor :delimiter, :delimiter_string
private
	def zero_out input
		output = input.dup
		idx = 0
		# Look for the closest block
		while true
			block_start, opener_length, opener, closer = @blocks.map { |opener, closer|
				md = output.match(opener, idx)
				[md && md.begin(0), md && md[0].length, opener, closer]
			}.reject { |e| e.first.nil? }.min_by(&:first)
			break if block_start.nil?

			md = output.match closer, block_start + opener_length
			idx = block_end = md ? md.end(0) : (output.length-1)

			output[block_start...block_end] = ' ' * (block_end - block_start)
		end
		output
	end

	def next_statement
		@cur = 0

		while process_next_block != :done
		end

		ret = @input[0...@cur].strip
		@input   = @input[@cur..-1]
		@input_c = @input_c[@cur..-1]
		return ret
	end

	def process_next_block expect = nil
		# Look for the closest delimiter
		md = @input_c.match @delimiter, @cur
		delim_start = md ? md.begin(0) : @input.length
		delim_end   = md ? md.end(0) : @input.length

		# Look for the closest block
		target_blocks = 
			if @options[:nesting_context].any? {|pat| @input_c.gsub($/, ' ').match pat }
				@all_blocks
			else
				@blocks
			end

		block_start, body_start, opener, closer = target_blocks.map { |opener, closer|
			closer = closer[:closer] if closer.is_a? Hash
			md = @input_c.match(opener, @cur)
			[md && md.begin(0), md && md.end(0), opener, closer]
		}.reject { |e| e.first.nil? }.min_by(&:first)

		# If we're nested, look for the parent's closer as well
		if expect && (md = @input_c.match expect, @cur) &&
				(block_start.nil? || md.begin(0) < block_start)

			@cur = md.end(0)
			return :nest_closer
		end
	
		# No block until the next delimiter
		if block_start.nil? || block_start > delim_start
			@cur = delim_end
			return :done
		end

		# #####################################

		# We found a block. Look for the end of it
		@cur = body_start

		# If nesting block, we go deeper
		if @nblocks.keys.include? opener
			while true
				ret = process_next_block(closer)
				break if ret == :nest_closer
				throw_exception(closer) if @cur >= @input.length - 1
			end
			return :done if @nblocks[opener].is_a?(Hash) && @nblocks[opener][:pop]

		# If non-nesting block, just skip through it
		else
			skip_through_block closer
		end

		return :continue
	end

	def skip_through_block closer
		md = @input_c.match closer, @cur
		throw_exception(closer) if md.nil?

		@cur = md.end(0)
	end

	def throw_exception closer
		raise ArgumentError.new(
				"Unclosed block: was expecting #{closer.inspect} " +
				"while processing #{(@input[0, 60] + ' ... ').inspect}" + 
				(@prev_statement ?
					" after #{@prev_statement.inspect}" : ""))
	end
end#EachSQL

