require 'fastest-csv'

class DataTable
	attr_accessor :observations, :variables

	def initialize(opts = {})
		@file = opts[:file]							
		@label_index = opts[:label_index]
		@observations = FastestCSV.read(@file)
		@variables = @observations.first
		@observations.shift unless @label_index == :none

		if @file
			@observations.map! { |row| Observation.new(row, @label_index) }
		end
	end

	def persist(file)
		File.open(file, 'w+') { |f| f << Marshal.dump(self) }
	end

	def self.load(file)
		Marshal.load(File.binread(file))
	end	

	def sample
		@observations.sample
	end
end

class Observation
	attr_reader :label, :features
	
	def initialize(ary, label_index)
		if label_index == :none
			@label = :none
		else	
			@label = ary.delete_at(label_index).to_i
		end
		@features = ary.collect(&:to_i)
	end
end
