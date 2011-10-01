#!/usr/bin/env ruby
# Clockwork is a gem which provides cron-like functionality in Ruby. This script is run as a daemon:
# clockwork_jobs.rb start
# clockwork_jobs.rb stop
# When developing and debugging, run it in the foreground, not as a daemon:
# clockwork_jobs.rb run
require "rubygems"
require "daemons"

pid_path = File.join(File.dirname(__FILE__), "../tmp")
log_path = File.join(File.dirname(__FILE__), "../log")
daemonize_options = {
  :dir_mode => :script, # Place the pid file relative to this script's directory.
  :dir => pid_path,
  :log_dir => log_path,
  :log_output => true
}

# Note that Daemons changes the current working directory to / when it daemonizes a process (inside run_proc).
project_root = File.expand_path(File.join(File.dirname(__FILE__), "../"))

Daemons.run_proc("clockwork_jobs.rb", daemonize_options) do
  $LOAD_PATH.push(project_root) unless $LOAD_PATH.include?(project_root)
  require "clockwork"
  require "resque_jobs/fetch_commits"

  def clear_resque_queue(queue_name) Resque.redis.del("queue:#{queue_name}") end

  # We're enqueing Resque jobs to be performed instead of trying to actually perform the work here from within
  # the Clockwork process. This is recommended by the Clockwork maintainer. Since Clockwork is a
  # non-parallelized loop, you don't want to perform long-running blocking work here.
  # We're clearing out the queue for a job before pushing another item onto its queue, in case the job is
  # taking a very long time to run. We don't want to build up a backlog on the queue because clockwork is
  # moving faster than the job is.
  Clockwork.handler do |job_name|
    case job_name
    when "fetch_commits"
      clear_resque_queue("fetch_commits")
      Resque.enqueue(FetchCommits)
    end
  end

  Clockwork.every(45.seconds, "fetch_commits")

  Clockwork.run # This is a blocking call.
end