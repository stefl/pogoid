When I'm hacking on something that *might* turn into an app with some legs, I often use Mongo and Mongoid. It's lovely, very malleable and easy to hack with. The thing is, you always reach a point where you want to do join. And you can't. And then you have to write some insane map reduce function in javascript and it takes ages and is confusing and slow.

So I flipped back to Active Record, mainly because my team prefer it, and in particular we're building a lot of stuff on Postgres. But it feels like operating in the past.

But then I discovered that you can do "hstore" and "json" columns natively in Postgres with some Active Record gems. And then I thought that actually it could be possible to do everything that's nice-for-hacking about Mongo in Active Record, if only it would get out of your way and stop forcing you to write migration files for every data model change.

Annoying.

I remembered that Datamapper is great at that kind of thing, but oh, the new version is stalled (understandably), and Rails 4 is about to land.

What to do? Find a new way...

Pogoid is a sketch of a way of declaring models so that it:

* Automatically creates a database
* Automatically creates tables based on your models
* Lets you declare properties in your model, just like Mongoid
* Automigrates your models to match the DB.
* Lets you choose between "columns" (actual Posgres DB columns ) versus "properties", things that you're kind of interested in making sure stick around in your DB but are stored in an hstore, "virtual" columns if you will

And soon it will":
* Let you put structured JSON objects into your model (TODO)
* Let you add migrations once you're at a stable point and need to add collaborators (TODO)

An example:

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

This is an experiment and as always is built on the shoulders of giants!