
require 'rubygems'
require 'pg'
require 'active_record'
require 'yaml'
require 'mini_record'
require 'hstore-attributes'
require 'activerecord-postgres-hstore'
require 'active_support/inflector'


# Auto-create the database. I really can't be bothered setting it up
begin
  dbconfig = YAML::load(File.open('database.yml'))
  conn = PG.connect( dbname: dbconfig["database"], user: dbconfig["username"], :password => dbconfig["password"])
  conn.close
  ActiveRecord::Base.establish_connection(dbconfig)
rescue PG::Error => e
  puts "Database does not exist, creating it."
  puts `createdb #{dbconfig["database"]} --user #{dbconfig["username"]}`
  retry
end

# I want to be able to work with properties on my models
# and don't really care how they are serialized
# "column" creates a database column by auto-migrating it
# "prop" creates a virtual column inside the "properties" hstore
# Passing "accessible" makes it attr_accessible in the same line as defining it
module Pogoid

  def self.add_model model
    @@models ||= []
    @@models << model
  end

  def self.finalize!
    @@models.each do |model|
      model.finalize!
    end
  end

  def self.included base
    Pogoid.add_model base
    base.extend(ClassMethods)
    base.col :properties, :type => :hstore
    base.col :created_at, :type => :datetime
    base.col :updated_at, :type => :datetime
    base.serialize :properties, ActiveRecord::Coders::Hstore
  end

  module ClassMethods
    def prop prop_name, prop_type, options
      @@props ||= {}
      @@props[prop_name] = prop_type
      if options[:accessible]
        attr_accessible prop_name
      end
    end

    def column column_name, options
      col column_name, options
      if options[:accessible]
        attr_accessible column_name
      end
    end

    def finalize!
      if @@props
        hstore :properties, :accessors => @@props
      end
      auto_upgrade!
    end

  end
end

# Now for the nice part. You're hacking away sketching out models.
# Define "props" as you need them. "column" for things you know you need a migration for
class User < ActiveRecord::Base
  include Pogoid
  column :name, :type => :string, :accessible => true
  prop :happiness, :integer, :accessible => true
  has_many :ideas
end

class Idea < ActiveRecord::Base
  include Pogoid
  column :name, :type => :string, :accessible => true
  column :user_id, :type => :integer, :accessible => true
  prop :silliness, :integer, :accessible => true
  prop :originality, :float, :accessible => true
  belongs_to :user
end

Pogoid.finalize! # call this after your model definitions

user = User.create!(:name => "Stef", :happiness => 1)
idea = Idea.create!(
  :name => "A way to work a bit faster with AR",
  :silliness => 4,
  :originality => 0.5,
  :user_id => user.id
  )