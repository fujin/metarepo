require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

require 'metarepo/repo'
require 'metarepo/package'
require 'metarepo/upstream'
require 'metarepo/pool'

describe Metarepo::Repo do
  before(:each) do
    @repo = Metarepo::Repo.new
    @repo.name = "shadows_fall"
    @repo.type = "yum"
    @repo.path = File.join(SPEC_SCRATCH, "repos", "shadows-fall")
    @repo.repo_dir = File.join(SPEC_SCRATCH, "repos")
    @repo.save
    @upstream = Metarepo::Upstream.create(:name => "centos-6.0-os-i386", :type => "yum", :path => File.join(SPEC_DATA, "/upstream/centos/6.0/os/i386/Packages"))
    @upstream.sync_packages
    @pool_dir = File.join(SPEC_SCRATCH, "pool")
    @pool = Metarepo::Pool.new(@pool_dir)
    @pool.update
  end

  describe "name" do
    it "must be unique" do
      lambda { 
        o = Metarepo::Repo.create(:name => "shadows_fall", :type => "yum", :path => "/foo")
      }.should raise_error(Sequel::ValidationFailed)
    end
  end


  describe "type" do
    it "must be present" do
      lambda { 
        Metarepo::Repo.create(:name => "Shadows Falling", :path => "/foo")
      }.should raise_error(Sequel::ValidationFailed)
    end

    [ "yum", "apt", "dir" ].each do |type_name|
      it "can be #{type_name}" do
        @repo.type = type_name
        lambda { @repo.save }.should_not raise_error(Sequel::ValidationFailed)
      end
    end

    it "raises an error on other values" do
      @repo.type = "frobnobbery"
      lambda { @repo.save }.should raise_error(Sequel::ValidationFailed)
    end
  end

  describe "link_package" do
    it "should create the directory for the file" do
      @repo.link_package(@upstream.packages.detect { |p| p.name == "basesystem" }, @pool)
      Dir.exists?(@repo.repo_dir).should == true
    end

    it "should link in package from the pool to the repo" do
      package = @upstream.packages.detect { |p| p.name == "basesystem" }
      @repo.link_package(package, @pool)
      File.exists?(File.join(@repo.repo_dir, @repo.name, package.filename)).should == true
    end

    it "should be added to the list of packages in use on this repo" do
      @repo.link_package(@upstream.packages.detect { |p| p.name == "basesystem" }, @pool)
      @repo.packages.detect { |p| p.name == "basesystem" }.should be_a_kind_of(Metarepo::Package)
    end

    it "does not hardlink in the package file from the pool if it exists" do
      package = @upstream.packages.detect { |p| p.name == "basesystem" }
      @repo.link_package(package, @pool)
      lambda { @repo.link_package(package, @pool) }.should_not raise_error(Errno::EEXIST)
    end
  end

  describe "unlink_package" do
    it "removes the package from the repo" do
      package = @upstream.packages.detect { |p| p.name == "basesystem" }
      @repo.link_package(package, @pool)
      File.exists?(File.join(@repo.repo_dir, @repo.name, package.filename)).should == true
      @repo.packages.detect { |p| p.name == "basesystem" }.should be_a_kind_of(Metarepo::Package)
      @repo.unlink_package(package, @pool)
      File.exists?(File.join(@repo.repo_dir, @repo.name, package.filename)).should == false 
      @repo.packages.detect { |p| p.name == "basesystem" }.should == nil
    end

    it "should not throw an error if you unlink twice" do
      package = @upstream.packages.detect { |p| p.name == "basesystem" }
      @repo.link_package(package, @pool)
      @repo.unlink_package(package, @pool)
      lambda { @repo.unlink_package(package, @pool) }.should_not raise_error(Errno::ENOENT)
    end
  end

  describe "sync_to_upstream" do
    it "links all the packages from the upstream to the repo through the pool" do
      @repo.sync_to_upstream(@upstream.name, @pool)
      @upstream.packages.each do |package|
        File.exists?(File.join(@repo.repo_dir, @repo.name, package.filename)).should == true
      end
    end

    it "removes files that were in the upstream, but are not any longer" do
      @repo.sync_to_upstream(@upstream.name, @pool)
      @upstream.packages.each do |package|
        File.exists?(File.join(@repo.repo_dir, @repo.name, package.filename)).should == true
      end
      remove_package = Metarepo::Package[:name => "basesystem"]
      @upstream.remove_package(remove_package)
      @repo.sync_to_upstream(@upstream.name, @pool)
      File.exists?(File.join(@repo.repo_dir, @repo.name, remove_package.filename)).should == false
      @repo.packages.detect { |o| o.name == "basesystem" }.should == nil
    end
  end

  describe "update_index_yum" do
    it "pauses" do
      @repo.sync_to_upstream(@upstream.name, @pool)
      @repo.update_index_yum
      File.exists?(File.join(@repo.repo_dir, @repo.name, "repodata", "repomd.xml"))
    end
  end

  describe "update_index" do
    it "creates yum indexes for yum repositories" do
      @repo.sync_to_upstream(@upstream.name, @pool)
      @repo.update_index 
      File.exists?(File.join(@repo.repo_dir, @repo.name, "repodata", "repomd.xml"))
    end
  end
end


