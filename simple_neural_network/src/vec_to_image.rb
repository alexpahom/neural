require 'chunky_png'
require './data_loader.rb'
require 'pry'
require 'csv'

class VectoImage
	attr_reader :dt, :small_images
	SIZE = 28
	def initialize(images_wide, images_high, params = {})
		@small_images = []
		@dt = read_data params
		build_image(images_wide, images_high).save('../data/images/mnist.png') unless params[:handmade]

		CSV.open('../data/manual_test_set.csv', 'wb') do |csv|
			@small_images.each do |image|
				csv << image
			end
		end
	end

	def read_data(params = {})
		if params[:handmade]
			upload_handmade
		else
			DataTable.load('../data/train.data')
		end
	end

	private

	def upload_handmade
		pixels = ChunkyPNG::Image.from_file('handmade.png').pixels
			.map! { |el| el = 0 if el != 255 }
		CSV.open('handmade.csv', 'wb') { |csv| csv << pixels }
		DataTable.new(file: 'handmade.csv', label_index: :none)
	end

	def build_image(wide, high)
		image = ChunkyPNG::Image.new(wide * SIZE, high * SIZE)
		wide.times do |i|
			high.times do |j|
				small_image = dt.sample.features
				@small_images << small_image
				small_image.size.times do |k|
					#colored version -- image[(i)*(28) + (k % 28),(j)*(28) + (k / 28)] = ChunkyPNG::Color.rgb((small_image[k] * s2).ceil,(small_image[k] * s3).ceil,(small_image[k] * s1).ceil)
					image[i * SIZE + k % SIZE, j * SIZE + k / SIZE] = ChunkyPNG::Color.grayscale(small_image[k])
				end
				print '.'
			end
		end
		puts
		image
	end
end

# VectoImage.new(1,1, handmade: true)
VectoImage.new 5, 5

