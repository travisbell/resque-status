require 'bundler/setup'
require 'resque-status'

require 'minitest/autorun'
begin
  require 'mocha/minitest'
rescue LoadError
  require 'mocha/setup' # mocha < 1.0
end

if ENV['REDIS_URL']
  # A disposable server (the tests flush it), e.g. `docker run --rm -p 9736:6379 redis`.
  Resque.redis = ENV['REDIS_URL']
else
  #
  # make sure we can run redis
  #

  if !system("which redis-server")
    puts '', "** can't find `redis-server` in your path, or set REDIS_URL to a disposable server"
    puts "** try running `sudo rake install`"
    abort ''
  end

  #
  # start our own redis when the tests start,
  # kill it when they end
  #

  class << Minitest
    def exit(*args)
      pid = `ps -e -o pid,command | grep [r]edis.*9736`.split(" ")[0]
      # Without a pid, Process.kill would signal this whole process group.
      if pid
        puts "Killing test redis server..."
        Process.kill("KILL", pid.to_i)
      end
      super
    end
  end

  dir = File.expand_path("../", __FILE__)
  puts "Starting redis for testing at localhost:9736..."
  result = `rm -f #{dir}/dump.rdb && redis-server #{dir}/redis-test.conf`
  raise "Redis failed to start: #{result}" unless $?.success?
  Resque.redis = 'localhost:9736/1'
end

#### Fixtures

class WorkingJob

  include Resque::Plugins::Status

  def perform
    total = options['num']
    (1..total).each do |num|
      at(num, total, "At #{num}")
    end
  end

end

class ErrorJob

  include Resque::Plugins::Status

  def perform
    raise "I'm a bad little job"
  end

end

class KillableJob
  include Resque::Plugins::Status

  def perform
    Resque.redis.set("#{uuid}:iterations", 0)
    100.times do |num|
      Resque.redis.incr("#{uuid}:iterations")
      at(num, 100, "At #{num} of 100")
    end
  end

end

class BasicJob
  include Resque::Plugins::Status
end

class FailureJob
  include Resque::Plugins::Status

  def perform
    failed("I'm such a failure")
  end
end

class NeverQueuedJob
  include Resque::Plugins::Status

  def self.before_enqueue(*args)
    false
  end

  def perform
    # will never get called
  end
end
