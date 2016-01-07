require "bundler/setup"
require "nokogiri"
require "circleci"
require "active_record"
require 'dotenv'
Dotenv.load

tkn = ENV['CI_TOKEN']

CircleCi.configure do |config|
  config.token = tkn
end

$token = "?circle-token=#{tkn}"
$username = ENV['CI_USERNAME']
$repo = ENV['CI_REPOSITORY']


def download_rspec_results_from build
  res = CircleCi::Build.artifacts $username, $repo, build
  rspec_reports = res.body.inject([]){|array,e|array[e["node_index"]] = e["url"] if e["url"] =~ /rspec\/result.xml$/ ; array}
  build_folder = "builds/#{build}"

  `mkdir -p #{build_folder}`

  rspec_reports.each_with_index do |url, i|
    destination_file = "builds/#{build}/container#{i}.xml"
    if !File.exists?(destination_file) || File.size(destination_file) == 0
      `curl #{url+$token} | sed 's/ classname=.* file=/ file=/' > #{destination_file}`
    end
    yield destination_file if block_given?
  end
  Dir["#{build_folder}/*.xml"]
end

def parse_reports containers
  containers.map do |container|
    doc = File.open(container) { |f| Nokogiri::XML(f)  }
    doc.xpath("//testcase").inject({}) do |total_spec, spec_item|
      t = spec_item['time'].to_f
      total_spec[spec_item['file']] ||= 0
      total_spec[spec_item['file']] += t
      total_spec
    end
  end
end

ActiveRecord::Base.establish_connection(
  adapter:    'postgresql',
  host:       'localhost',
  database:   'circleci',
  port:       '15432'
)

class Performance < ActiveRecord::Base

end


def persist build, spec_results
  spec_results.each_with_index do |results,container|
    results.each {|file,time| Performance.create build: build, container: container, file: file, time: time }
  end
end

def fetch build
  containers = download_rspec_results_from build
  spec_results = parse_reports containers
  Performance.where(build: build).delete_all
  persist build, spec_results
end

#fetch "32393"

def time_per_file
  @time_per_file ||= Performance.group(:file).average(:time)
end

def stdev_per_file 
  @stdev_per_file ||= Performance
    .select("file, stddev_samp(time) as time")
    .group(:file)
    .inject({}){|h,performance|h[performance.file] = performance.time;h}
end

def compare_build build_num
  time_per_file.each do |file, avg_time|
    next unless stdev_per_file[file]
    result = Performance.where(build: build_num, file: file).where("time - #{avg_time} < #{stdev_per_file[file] * 10}") #melhorou 10%
    if result.exists?
      puts "#{file} melhorou em #{ result.first.time - avg_time} < #{} segundos (#{result.first.time} -> ~#{ avg_time} ^#{stdev_per_file[file]})"
    end
  end
end


builds = CircleCi::Project.recent_builds $username, $repo
build_nums = builds
  .body
  .select{|e|e["status"] =~ /fixed|success/ && e["branch"] !="master"}
  .map{|e|e["build_num"]}

build_nums.each{|build_num| fetch build_num }
require "pry"
binding.pry

