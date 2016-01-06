# Green circle


It downloads artifacts from your Circle CI and persists into a database.
Allowing you to study performance per build.

## Setup your key

1. Create or get your key on [Circle CI api](https://circleci.com/account/api).
2. Set as a environment variable

     export CI_TOKEN=myAwesomeToken
     export CI_REPOSITORY="rdstation"
     export CI_USERNAME="ResultadosDigitais"

3. Setup your database
 
```sql
create database circleci;
\c circleci
create table performances (build integer, file varchar, time float, container integer)
```

3. Choose recent builds to analyse

Supose you get a list of your recent successful builds:

```ruby
builds = CircleCi::Project.recent_builds $username, $repo
build_nums = builds
  .body
  .select{|e|e["status"] =~ /fixed|success/ && e["branch"] !="master"}
  .map{|e|e["build_num"]}
```

So, fetch and persist data:

```ruby
build_nums.each{|build_num| fetch build_num }
```

4. Now explore!

### Average build time

```ruby
Performance.group(:build).average(:time)
```

### Average build time by container

```ruby
Performance.group(:build, :container).average(:time)
```

### Standard deviation of time per file

```ruby
stdev_per_file
```