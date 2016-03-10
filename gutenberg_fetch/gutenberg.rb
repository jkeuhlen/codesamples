#puts "Hello World!\n"

# Author: Jake Keuhlen (jak1214@gmail.com)
# Env: ruby 2.1.5 x86_64 linux (Ubuntu 14.04)
# Gems: gutenberg_rdf : https://github.com/mrcook/gutenberg_rdf
#       google_hash :   https://github.com/rdp/google_hash

# The purpose of this file is to download a specified book from
#  project gutenberg. It was written as a response to the following 
#  requirements:
# 		Accept a parameter from a user
# 		Find a file on the internet based on the parameter
# 		Return the file to the user

# Here our parameter is the name of a classic book in the public domain.
# The file is looked up in Project Gutenberg's catalog and confirmed with
#  the user. 
# The file is then downloaded for the user. 
# The catalog is downloaded from https://www.gutenberg.org/wiki/Gutenberg:Feeds
# The catalog should be untared and stored in the same directory as this script with the 
#  format cache/epub/###/pg###.rdf
# If the script has not been run before, 
#  it will set up the environment first by downloading and processing the catalog in the needed way.
# Or a user can set it up manually following instructions in the comments throughout this file.
# If you aren't sure what books you may want to download, use Project Gutenberg's list of the top 100 downloads: https://www.gutenberg.org/browse/scores/top

##### WARNING #####
# Project Gutenberg does not like bots crawling their site all the time. As such, if you run this to download tons of files, they may ban your IP address. 
# More information is available here: https://www.gutenberg.org/wiki/Gutenberg:Information_About_Robot_Access_to_our_Pages
# They provide how to get certain files using wget, so I THINK my implementation is okay.
# The URI used is patched over to use a mirror site like they ask you to in the Terms of use
#  This complicates things since the RDF catalog contains links to the main site, but the mirrors
#  use a different structure.


require 'gutenberg_rdf'
require 'google_hash'
require 'yaml'

# Globals
@base_dir = "./cache/epub/"
@verbose = 1

##### Helpers #####

# I want to flatten my titles to allow for spelling mistakes on the user's part
# TODO Ideally, this would also map what most people think is the title of a book to the actual title of the book, or the hashing could fall back to a search of the YAML file for the coresponding ID for the closest match. An example:
# Gullivers Travel -> Gulliver's Travels into Several Remote Nations of the World
def flatten_title(title)
  return title.strip.downcase
end


# Environment setup if the catalog is missing.
def setup()
  # Quick exit if the base directory has been setup already
  if (File.directory?(@base_dir))
    return
  end
  puts
  puts "Setting up your environment. This should only take a minute."
  puts
  # This uri is the one for robots to grab the catalog, if you want to download it yourself it is
  # https://www.gutenberg.org/cache/epub/feeds/rdf-files.tar.zip
  catalog_uri = "http://gutenberg.pglaf.org/cache/generated/feeds/rdf-files.tar.zip"
  start = Time.now
  system("wget -w 2 -m -H #{catalog_uri} -nH -nd") 
  system("gunzip < rdf-files.tar.zip | tar xf -")
  Dir.chdir(@base_dir) do
    # Ruby defaults to using /bin/sh but I specifically want to run this in the bash shell so that read has the -d option
    system("bash", "-c", "grep -rLZ \":title\" . | while IFS= read -rd \'\' x; do rm -f \"$x\"; done")
  end
  end_time = Time.now
  ttr = end_time-start
  print "Time to set up catalog: " if @verbose
  puts ttr if @verbose
end

# This helper method gets the correct path to a book stored on the gutenberg.pglaf.org mirror
def get_mirror_uri(id, type)
  # The path changes between what's in the catalog RDF and the mirror structure so it needs patching.
  # Note that mobi format is the same as kindle (their naming convention changed on miror)
  base = "gutenberg.pglaf.org/cache/epub/"
  uri = base + id.to_s + "/"
  case type
  when /kindle.images/
    uri += "pg#{id}-images.mobi"
  when /kindle.noimages/
    uri += "pg#{id}.mobi"
  when /.txt/
    uri += "pg#{id}.txt.utf8"
  when /epub.images/
    uri += "pg#{id}-images.epub"
  when /epub.noimages/
    uri += "pg#{id}.epub"
  end

  # A return is unneeded since it is implied, but let's be explicit
  return uri
end

##### MAIN #####
books = []
# The GoogleHash implements a more efficient hash algorithm that should speed things up here.
# But I can't serialize it to YAML as easily. 
# TODO Need to investigate that more. 
#titles = GoogleHashDenseRubyToLong.new
titles = {}
#download_dir = "~/Downloads/"
download_dir = "."
# The files need some cleanup to work properly with the gem. If they don't have a title, they won't parse and the script will choke. Run this from base_dir if you aren't using automated setup:
# grep -rLZ ":title" . | while IFS= read -rd '' x; do rm -f "$x"; done
# Then run this to make sure it comes back clean:
# grep -rLZ ":title" . | while IFS= read -rd '' x; do echo "$x"; done
# The problem is caused by books that were removed. They give a 404 error if you try to find them manually, but are still listed in the catalog since the catalog is auto-generated by crawling their own site.

# Call the setup method.
# If the environment you are running in does not have a copy of the catalog, 
#  go fetch one and clean it.
setup()


start = Time.now
# Populate hash of all known book titles
# This operation is expensive and shouldn't run every time. 
# Save its results to a config file in YAML format and load that if you can.
if (!File.file?("titles.yml"))
  # Inform user this may take awhile to start up if you don't have anything to load
  puts "This is going to take awhile to start up."
  puts "Come back in ten minutes."
  Dir.glob(@base_dir + "*/*.rdf") do |rdf|
    book = GutenbergRdf.parse(rdf)
    # I don't want audiobooks, only text
    #TODO Audiobooks could be combined but they are typically stored under a different path so save that for later
    if (!book.type.eql? "Text")
      next
    end
    flat_title = flatten_title(book.title.to_s)
    titles[flat_title] = [book.id.to_i, rdf]
  end
  File.open("titles.yml", "w") do |file|
    file.write titles.to_yaml
  end
else 
  puts "Loading titles from file: titles.yml"
  titles = YAML::load_file "titles.yml"
end
end_time = Time.now 
ttr = end_time-start
print "Time to load titles: " if @verbose
puts ttr if @verbose
puts
puts "I can fetch (almost) any classic piece of literature!"
puts "I have #{titles.length} books I can find for you."
puts 
puts "Enter the name of a book or (ex|qu)it to leave"

while true
  puts "What would you like me to download for you?"
  if ((input = gets.chomp) =~ /(?:ex|qu)it/i)
    break
  end
  puts "You want me to look for #{input}? Is that correct? [yes]" 
  resp = gets.strip
  unless (resp.empty? || resp.match(/^y[es]?/i))
    puts "Okay, let's try again."
    next
  end
  flattened_input = flatten_title(input)
  if (titles.key?(flattened_input))
    puts "I found it! This book is ID number #{titles[flattened_input][0]} on Project Gutenberg! I'll go fetch it for you."
  else 
    puts "Sorry, that didn't match anything in my records. Make sure you have the spelling correct!"
    next
  end
  puts "Here are your options for file format. Please select the corresponding number to download." 
  fetch = GutenbergRdf.parse(titles[flattened_input][1])
  fetch.ebooks.each_with_index do |opt, i|
    case opt.uri
    when /kindle.images$/
      puts "Kindle file with images     |   #{i}"
    when /kindle.noimages$/
      puts "Kindle file without images  |   #{i}"
    when /.txt$/
      puts "Plain text file             |   #{i}"
    when /epub.images$/
      puts "EPUB file with images       |   #{i}"
    when /epub.noimages$/
      puts "EPUB file without images    |   #{i}"
    end
  end
  resp = Integer(gets) rescue false 
  if (!resp)
    puts "Sorry, I didn't understand that input. Let's start over."
    next
  end
  type = fetch.ebooks[resp].uri.strip[/\d+(\.\w+.*)/, 1]
  uri = get_mirror_uri(fetch.id, type)
  puts "Attempting to get with this uri:"
  puts uri
  system("wget -w 2 -m -H #{uri} -P #{download_dir} -nH -nd")
  puts
  #TODO Rename the file to match the title of the book. 
end
