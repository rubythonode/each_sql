# encoding: UTF-8
# Junegunn Choi (junegunn.c@gmail.com)

require 'rubygems'
require 'each_sql/each_sql'
require 'each_sql/parser'

# Shortcut method for creating a Enumerable EachSQL object for the given input.
# @param[String] input Input script.
# @param[Symbol] The type of the input SQL script. :default, :mysql, and :oracle (or :plsql)
# @yield[String] Executable SQL statement or block.
# @return[Enumerator] Enumerator of executable SQL statements and blocks.
def EachSQL input, type = :default
  return enum_for(:EachSQL, input, type) unless block_given?

  esql   = EachSQL.new(type)
  result = {}

  process = lambda {
    return if esql.empty?
    result = esql.shift
    sqls   = result[:sqls]
    sqls.each do |sql|
      yield sql
    end
  }

  input.to_s.each_line do |line|
    case line
    when /^\s*delimiter\s+(\S+)/i
      process.call
      if esql.empty?
        esql.delimiter = $1
      else
        esql << line
      end
    when /#{Regexp.escape esql.delimiter}/
      esql << line
      process.call
    else
      esql << line
    end
  end

  if !esql.empty?
    process.call
  end

  if sql = result[:leftover]
    yield sql
  end
end

