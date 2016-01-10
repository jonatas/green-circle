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
	begin 
  res = CircleCi::Build.artifacts $username, $repo, build
	rescue SocketError
		puts "Ops!!! #{$!} retry in 2 seconds..."
		sleep 2
		retry
	end
  rspec_reports = res.body.inject([]){|array,e|array[e["node_index"]] = e["url"] if e["url"] =~ /rspec\/result.xml$/ ; array}
  build_folder = "builds/#{build}"

  `mkdir -p #{build_folder}`

  rspec_reports.each_with_index do |url, i|
    next if not url

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
  port:       '5432'
)

class Performance < ActiveRecord::Base

 scope :time_per_file, -> { group(:file).average(:time) }
 scope :build_time_per_container, -> {
   h = {}
   Performance.group(:build, :container).sum(:time).each do |(build_num, container), time|
    h[build_num] ||= [] 
    h[build_num][container]  = time
  end
  h
 }
 scope :stdev_per_file, -> {
    select("file, stddev_samp(time) as time")
    .group(:file)
    .inject({}){|h,performance|h[performance.file] = performance.time;h}
  }

  def self.save_parsed_results build, spec_results
    where(build: build).delete_all
    spec_results.each_with_index do |results,container|
      results.each {|file,time| create build: build, container: container, file: file, time: time }
    end
  end
end

class Build < ActiveRecord::Base

  scope :grouped, -> (by) { group(by).count.sort_by{|k,v|k || ""} }
  scope :in, -> (trunk, value) { where("extract(? from start_time) = ?", trunk, value) }

  scope :per_hour, -> { grouped("extract(hour from start_time)") }
  scope :per_dow, -> { grouped("extract(dow from start_time)") }
  scope :per_year_month, -> { grouped("to_char(start_time, 'YYYY/MM')") }
  scope :per_year_month_and_user, -> { grouped("to_char(start_time, 'YYYY/MM') || ' ' || author_name") }

  scope :contributors, -> { select("author_name").distinct.pluck("author_name").compact.sort }
  scope :total,  -> (field){ select(field).distinct.count }
  scope :total_branches, -> { total("branch") }

  scope :top_contributors, -> { grouped("author_name").sort_by {|k,v|-v} }
  scope :top_branches, -> { grouped("branch").sort_by {|k,v|-v} }

  scope :total_contributors, -> { 
    where("not author_name is null")
      .where("not author_name = 'capybot'")
      .select("author_name").distinct }

  scope :worse_waiting_time, 
    -> { select("*, EXTRACT(EPOCH FROM (start_time - queued_at)) as waiting_time")
         .order("EXTRACT(EPOCH FROM (start_time - queued_at)) DESC")
         .map(&:attributes) }

  def self.save_from_json info
    where(build_num: info["build_num"]).delete_all
    create info.slice("build_num", "author_name","queued_at","start_time", "build_time_millis","branch", "subject")
  end
end



def fetch build
  containers = download_rspec_results_from build
  spec_results = parse_reports containers
  Performance.save_parsed_results build, spec_results
end

#fetch "32393"


def compare_build build_num
  stdev_per_file = Performance.stdev_per_file
  Performance.time_per_file.each do |file, avg_time|
    next unless stdev_per_file[file]
    result = Performance.where(build: build_num, file: file).where("time - #{avg_time} < #{stdev_per_file[file] * 10}") #melhorou 10%
    if result.exists?
      puts "#{file} melhorou em #{ result.first.time - avg_time} < #{} segundos (#{result.first.time} -> ~#{ avg_time} ^#{stdev_per_file[file]})"
    end
  end
end



def worse_build
  max_time = nil
  worse_build = nil
  Performance.build_time_per_container.each do |build, times|
    next if times.length < 4 || times.nil? || times.empty? || times.max.nil?
    if max_time.nil? || times.max > max_time.max 
      max_time = times
      worse_build = build
    end
  end
  {worse_build => max_time}
end

def best_build
  max_time = nil
  best_build = nil
  Performance.build_time_per_container.each do |build, times|
    if max_time.nil? || times.max < max_time.max
      max_time = times
      best_build = build
    end
  end
  {best_build => max_time}
end

def fetch_successful_builds page=0, total_per_page=20
	builds = CircleCi.http.get "/project/#{$username}/#{$repo}#{$token}&filter=successful&offset=#{page * total_per_page}&limit=#{total_per_page}"
	builds
		.body # ignoring master
    .select{|e|e["status"] =~ /fixed|success/ && e["branch"] !="master"}
end

def fetch_some_builds page = 0
  fetch_successful_builds(page)
    .each do |build| 
      print "."
      Build.save_from_json build
    end
    #.each do |build| 
    #  print ","
    #  fetch build["build_num"]
    #end
end

def r
	load 'go.rb'
end

require "pry"
binding.pry


