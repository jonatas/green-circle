require "bundler/setup"
require "nokogiri"
require "circleci"
require "active_record"

tkn = ENV['CI_TOKEN']
CircleCi.configure do |config|
  config.token = tkn
end

$token = "?circle-token=#{tkn}"

$username,$repo,build = "ResultadosDigitais/rdstation/32395".split("/")

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

# create database circleci;
# \c circleci
#  create table performances (build integer, file varchar, time float, container integer)
ActiveRecord::Base.establish_connection(
  adapter:    'postgresql',
  host:       'localhost',
  database:   'circleci',
  port:       '5432'
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

time_per_file = Performance.group(:file).average(:time)
stdev_per_file = Performance.select("file, stddev_samp(time) as time").group(:file).inject({}){|h,performance|h[performance.file] = performance.time;h}

time_per_file.each do |file, avg_time|
  next unless stdev_per_file[file]
  puts("time / #{avg_time} < #{stdev_per_file[file] * 3}") #melhorou 10%
  result = Performance.where(build: 32393, file: file).where("time - #{avg_time} < #{stdev_per_file[file] * 10}") #melhorou 10%
  if result.exists?
    puts "#{file} melhorou em #{ result.first.time - avg_time} < #{} segundos (#{result.first.time} -> ~#{ avg_time} ^#{stdev_per_file[file]})"
  end
end

require "pry"
binding.pry
