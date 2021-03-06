require './data_loader.rb'
require 'nmatrix'
require 'csv'
require 'optparse'
require 'pry'

class NeuralNet

  attr_reader :hidden_func, :output_func, :mode, :hidden_nodes, :alpha
  IMG_AREA = 784 # as the image is 28x28
  DIGITS_COUNT = 10

  def initialize(params = {})
    puts_hrow

    @hidden_func = params[:hidden_func]
    @output_func = params[:output_func]
    @mode = params[:mode]
    @hidden_nodes = params[:hidden_nodes]
    @error_history = []
    @classification_history = []
    @alpha = params[:alpha]
  end

  def go
    case mode
    when 'train'
      @dt = load_datatable
      train
    when 'eval'
      create_test_submission
    else
      puts "You have to set --mode to 'train' or 'eval'"
    end
  end

  def load_datatable
    DataTable.load('../data/train.data')
  rescue
    puts 'Loading file from disk'
    puts_hrow
    DataTable.new(file: '../data/mnist_digits/train.csv', label_index: 0).tap do |dt|
      dt.persist('../data/train.data')
    end
  end

  def initialize_new_weights
    # weight scaler for the first weight matrix. It is indirectly proportional to the input size.
    # It has to be, otherwise you will blow up your hidden layer. If you do not put in the deflator.
    # The first couple of iterations will work on large sums in the hidden layer.
    # Large sums are bad in neural networks.
    init_factor_1 = 0.01 / Math.sqrt(IMG_AREA + 1)
    init_factor_2 = 0.01 / Math.sqrt(hidden_nodes)

    # 785x300 in case of defaults
    input_to_hidden_shape = [IMG_AREA + 1, hidden_nodes]
    # 301x10 in case of defaults
    hidden_to_output_shape = [hidden_nodes + 1, DIGITS_COUNT]

    @w1 = (NMatrix.random(input_to_hidden_shape) - NMatrix.new(input_to_hidden_shape, 0.5)) * init_factor_1 # some basic matrix algebra, create a matrix with
    @w2 = (NMatrix.random(hidden_to_output_shape)  - NMatrix.new(hidden_to_output_shape, 0.5)) * init_factor_2
  end
  
  def load_trained_weights
    @w1 = Marshal.load(File.binread('../data/w1.txt')).to_nm
    @w2 = Marshal.load(File.binread('../data/w2.txt')).to_nm
  end

  def create_test_submission
   puts 'Creating submission'
   load_trained_weights
   @hidden_nodes = @w1.shape.last

    data_table = DataTable.new(file: '../data/manual_test_set.csv', label_index: :none)
    # data_table = DataTable.new(file: '../data/mnist_digits/test.csv', label_index: :none)

    CSV.open('../data/submission.csv', 'wb') do |csv|
      csv << %w(ImageID Digit)
      data_table.observations.each_with_index do |observation, i|
        print '.' if (i + 1) % 100 == 0
        puts if (i + 1) % 10000 == 0
        csv << [i + 1, forward(observation)]
      end
      puts
    end
  end 

  def forward(observation)
    # convert the features array into a NMatrix matrix and divide every element by 255.
    # the division scales down the input. The input vector is initialized with size
    # 1 bigger than the IMG_AREA. This is to accommodate the bias term
    a1 = observation.features.flatten.to_nm([1, IMG_AREA + 1]) / 255.0

    # Set the bias term equal to 1
    a1[0, IMG_AREA] = 1.0

    # pass the product of the input values and the weight forward
    # and sum the product up at each node
    z2 = a1.dot(@w1)

    # apply the activation function to the sum vector element wise
    a2 = activation_function(z2, hidden_func)

    # resize the hidden layer to add the bias unit
    a2_with_bias = NMatrix.zeroes([1, hidden_nodes + 1]).tap do |matrix|
      matrix[0, 0..hidden_nodes] = a2
      matrix[0, hidden_nodes] = 1.0
    end

    #z3 = a2 x @w2, propogating the hidden layer forward to get the sums in the output layer
    z3 = a2_with_bias.dot(@w2)

    #Softmax activation function in the output layer
    a3 = activation_function(z3, @output_func)

    # if in training mode, pass values of layers to backprop.
    # otherwise return the prediction the output layer
    case mode
    when 'train'
      backprop(a1, a2_with_bias, z2, z3, a3, observation.label)
    when 'eval'
      return a3.each_with_index.max[1]
    end
  end
  
def backprop(a1, a2_with_bias, z2, z3, a3, label)
  # initiates the output vector of zeroes
  y = NMatrix.zeroes([1, 10])

  # set the label from the data to 1
  # only 1 element can be 1 at a time as classes
  # are mutually exclusive
  y[0, label] = 1.0
  
  # derivative of the loss function. Difference between predicted
  # values and the true value
  d3 = -(y - a3)  

  # using the derivative d3 is a good enough measure to
  # see if the cost is decreasing so we append it to
  # the error history
  @error_history << d3.transpose.abs.sum[0]
  
  # add 1 to the classification history if the prediction is correct, otherwise zero
  @classification_history << (a3.each_with_index.max[1] == label ? 1.0 : 0.0)
    
  # derivative, has the same size as the hidden layer. The range [] operator
  # excludes the bias node. No error is passed to the bias node.  
  d2 = @w2.dot(d3.transpose)[0..(@hidden_nodes-1)] * derivative(z2.transpose, @hidden_func)
  
  # matrix with dimensions equal to @w1's dimensions each element contains the
  # gradient of the weight with respect to the cost function. If the weights
  # are reduced by a small fraction of this value the cost function will go down
  grad1 = d2.dot(a1)
  
  # same for @w2
  grad2 = d3.transpose.dot(a2_with_bias)

  # updating the weigh matrices. The first layer is updated
  # by a factor of 10 less than than the second layer. for numerical
  # stability. Big weight changes -> big weights -> equals big sums -> saturated neurons
  @w1 -= grad1.transpose * alpha * 0.1
  @w2 -= grad2.transpose * alpha
end

def train
  puts 'Entered Training'
  i = 0
  start_time = Time.now
  initialize_new_weights
    
  loop do 
    # forward pass in the network with a random observation from @dt.sample.
    # its results go to the backprop method. The backprop method will update the weights
    forward(@dt.sample)

    avg_error_history_1k = running_average(1000, @error_history)
    avg_error_history_5k = running_average(5000, @error_history)
    avg_classification_history_1k = running_average(1000, @classification_history)
    avg_classification_history_5k = running_average(5000, @classification_history)
    ratio = avg_classification_history_1k / avg_classification_history_5k

    puts "Average Error (1000)          => #{avg_error_history_1k}"
    puts "Average Error (5000)          => #{avg_error_history_5k}"
    puts "Average Classification (1000) => #{avg_classification_history_1k}"
    puts "Average Classification (5000) => #{avg_classification_history_5k}"
    puts "Classification Average Ratio  => #{ratio}"
  
    puts "Iteration = #{i}"
    puts "---"

    #if ratio < 1.0 and i > 2000
    if ratio < 1.0 and i > 60000
      finish_time = Time.now
      File.open('../data/w1.txt', 'w') { |f| f << Marshal.dump(@w1.to_a) }
      File.open('../data/w2.txt', 'w') { |f| f << Marshal.dump(@w2.to_a) }
      puts "Total training time was: #{(finish_time - start_time).round(0)} sec"
      break
    end

  i += 1
  end
end 

  # arithmetic average
  def running_average(scale, array)
    array.last(scale).sum.to_f / [scale, array.size].min
  end 

  def sigmoid(mat)
    ones = Matrix.ones(mat.shape)
    ones / (ones + (-mat).exp)
  end

  def tanh(mat)
    ( (mat).exp - (-mat).exp )/( (mat).exp + (-mat).exp )
  end

  def softmax(mat)
    mat.map! { |el| Math::exp(el) }
    sum = mat.to_a.sum
    mat.map { |el| el / sum }
  end

  def activation_function(mat, func)
    case func
    when 'sigmoid'; sigmoid(mat)
    when 'tanh'; tanh(mat)
    when 'softmax'; softmax(mat)
    end
  end

  def derivative(mat, func)
    ones = NMatrix.ones(mat.shape)
    case func
    when 'sigmoid'
      sigmoid(mat) * (ones - sigmoid(mat))
    when 'tanh'
      (ones - tanh(mat)) * (ones + tanh(mat))
    end
  end

  def puts_hrow
    puts "----------------------"   
  end 
end

options = {}

parser = OptionParser.new do|opts|
  opts.banner = "Usage: neural_net.rb [options]"

  opts.on('-a', '--alpha alpha', 'Sets alpha') do |alpha|
    options[:alpha] = alpha.to_f
  end

  opts.on('--hidden_func func', 'Sets Hidden Function') do |func|
    options[:hidden_func] = func
  end

  opts.on('--output_func h_func', 'Sets Output Function') do |h_func|
    options[:output_func] = h_func
  end

  opts.on('--hidden_nodes number', 'Set number of Hidden Nodes') do |number|
    options[:hidden_nodes] = number.to_i
  end

  opts.on('-m', '--mode mode', 'Mode') do |mode|
    options[:mode] = mode.to_s
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end

parser.parse!

options[:hidden_nodes] = 300 if options[:hidden_nodes].nil?
options[:hidden_func] = 'tanh' if options[:hidden_func].nil?
options[:output_func] = 'softmax' if options[:output_func].nil?
options[:alpha] = 0.05 if options[:alpha].nil?
options[:mode] = 'train' if options[:mode].nil?

options.each { |k, v| puts "#{k} set to #{v}" }

sleep 2
NeuralNet.new(options).go
