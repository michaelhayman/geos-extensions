
module Geos
  module ActiveRecord #:nodoc:
    class << self
      def geometry_columns?
        ::ActiveRecord::Base.connection.geometry_columns?
      end

      def geography_columns?
        ::ActiveRecord::Base.connection.geography_columns?
      end
    end

    # This little module helps us out with geometry columns. At least, in
    # PostgreSQL it does.
    #
    # This module will add a method called geometry_columns to your model
    # which will contain information that can be gleaned from the
    # geometry_columns table that PostGIS creates.
    #
    # You can also have the module automagically create some accessor
    # methods for you to make your life easier. These accessor methods will
    # override the ActiveRecord defaults and allow you to set geometry
    # column values using Geos geometry objects directly or with
    # PostGIS-style extended WKT and such. See
    # create_geometry_column_accessors! for details.
    #
    # === Caveats:
    #
    # * This module currently only works with PostGIS.
    # * This module doesn't really "get" PostgreSQL catalogs and schemas
    #   and such. That would be a little more involved but it would be
    #   nice if Rails was aware of such things.
    module SpatialColumns
      SPATIAL_COLUMN_OUTPUT_FORMATS = %w{ geos wkt wkb ewkt ewkb wkb_bin ewkb_bin }.freeze

      class InvalidGeometry < ::ActiveRecord::ActiveRecordError
        def initialize(geom)
          super("Invalid geometry: #{geom}")
        end
      end

      class SRIDNotFound < ::ActiveRecord::ActiveRecordError
        def initialize(table_name, column)
          super("Couldn't find SRID for #{table_name}.#{column}")
        end
      end

      class CantConvertSRID < ::ActiveRecord::ActiveRecordError
        def initialize(table_name, column, from_srid, to_srid)
          super("Couldn't convert SRID for #{table_name}.#{column} from #{from_srid} to #{to_srid}")
        end
      end

      def self.included(base) #:nodoc:
        base.extend(ClassMethods)
        base.send(:include, Geos::ActiveRecord::SpatialScopes)
      end

      module ClassMethods
        protected
          @geometry_columns = nil
          @geography_columns = nil

        public
          # Stubs for documentation purposes:

          # Returns an Array of available geometry columns in the
          # table. These are PostgreSQLColumns with values set for
          # the srid and coord_dimensions properties.
          def geometry_columns; end

          # Returns an Array of available geography columns in the
          # table. These are PostgreSQLColumns with values set for
          # the srid and coord_dimensions properties.
          def geography_columns; end

          # Force a reload of available geometry columns.
          def geometry_columns!; end

          # Force a reload of available geography columns.
          def geography_columns!; end

          # Grabs a geometry column based on name.
          def geometry_column_by_name(name); end

          # Grabs a geography column based on name.
          def geography_column_by_name(name); end

          # Returns both the geometry and geography columns for a table.
          def spatial_columns
            self.geometry_columns + self.geography_columns
          end

          # Reloads both the geometry and geography columns for a table.
          def spatial_columns!
            self.geometry_columns! + self.geography_columns!
          end

          # Grabs a spatial column based on name.
          def spatial_column_by_name(name)
            self.geometry_column_by_name(name) || self.geography_column_by_name(name)
          end

          %w{ geometry geography }.each do |m|
            src, line = <<-EOF, __LINE__ + 1
              def #{m}_columns
                if @#{m}_columns.nil?
                  @#{m}_columns = connection.#{m}_columns(self.table_name)
                  @#{m}_columns.freeze
                end
                @#{m}_columns
              end

              def #{m}_columns!
                @#{m}_columns = nil
                #{m}_columns
              end

              def #{m}_column_by_name(name)
                @#{m}_column_by_name ||= self.#{m}_columns.inject(HashWithIndifferentAccess.new) do |memo, obj|
                  memo[obj.name] = obj
                  memo
                end
                @#{m}_column_by_name[name]
              end
            EOF
            self.class_eval(src, __FILE__, line)
          end

          # Quickly grab the SRID for a geometry column.
          def srid_for(column_name)
            column = self.spatial_column_by_name(column_name)
            column.try(:srid) || Geos::ActiveRecord.UNKNOWN_SRID
          end

          # Quickly grab the number of dimensions for a geometry column.
          def coord_dimension_for(column_name)
            self.spatial_column_by_name(column_name).coord_dimension
          end

        protected
          # Sets up nifty setters and getters for spatial columns.
          # The methods created look like this:
          #
          # * spatial_column_name_geos
          # * spatial_column_name_wkb
          # * spatial_column_name_wkb_bin
          # * spatial_column_name_wkt
          # * spatial_column_name_ewkb
          # * spatial_column_name_ewkb_bin
          # * spatial_column_name_ewkt
          # * spatial_column_name=(geom)
          # * spatial_column_name(options = {})
          #
          # Where "spatial_column_name" is the name of the actual
          # column.
          #
          # You can specify which spatial columns you want to apply
          # these accessors using the :only and :except options.
          def create_spatial_column_accessors!(options = nil)
            options = {
              :geometry_columns => true,
              :geography_columns => true
            }

            create_these = []

            if options.nil?
              create_these.concat(self.spatial_columns)
            else
              if options[:geometry_columns]
                create_these.concat(self.geometry_columns)
              end

              if options[:geography_columns]
                create_these.concat(self.geography_columns)
              end

              if options[:except] && options[:only]
                raise ArgumentError, "You can only specify either :except or :only (#{options.keys.inspect})"
              elsif options[:except]
                except = Array(options[:except]).collect(&:to_s)
                create_these.reject! { |c| except.include?(c) }
              elsif options[:only]
                only = Array(options[:only]).collect(&:to_s)
                create_these.select! { |c| only.include?(c) }
              end
            end

            create_these.each do |k|
              src, line = <<-EOF, __LINE__ + 1
                def #{k.name}=(geom)
                  if !geom
                    self['#{k.name}'] = nil
                  else
                    column = self.class.spatial_column_by_name(#{k.name.inspect})

                    if geom =~ /^SRID=default;/i
                      geom = geom.sub(/default/i, column.srid.to_s)
                    end

                    geos = Geos.read(geom)

                    if column.spatial_type != :geography
                      geom_srid = if geos.srid == 0 || geos.srid == -1
                        Geos::ActiveRecord.UNKNOWN_SRIDS[column.spatial_type]
                      else
                        geos.srid
                      end

                      if column.srid != geom_srid
                        if column.srid == Geos::ActiveRecord.UNKNOWN_SRIDS[column.spatial_type] || geom_srid == Geos::ActiveRecord.UNKNOWN_SRIDS[column.spatial_type]
                          geos.srid = column.srid
                        else
                          raise CantConvertSRID.new(self.class.table_name, #{k.name.inspect}, geom_srid, column.srid)
                        end
                      end

                      self['#{k.name}'] = geos.to_ewkb
                    else
                      self['#{k.name}'] = geos.to_wkb
                    end
                  end

                  SPATIAL_COLUMN_OUTPUT_FORMATS.each do |f|
                    instance_variable_set("@#{k.name}_\#{f}", nil)
                  end
                end

                def #{k.name}_geos
                  @#{k.name}_geos ||= Geos.from_wkb(self['#{k.name}'])
                end

                def #{k.name}(options = {})
                  format = case options
                    when String, Symbol
                      options
                    when Hash
                      options = options.stringify_keys
                      options['format'] if options['format']
                  end

                  if format
                    if SPATIAL_COLUMN_OUTPUT_FORMATS.include?(format)
                      return self.send(:"#{k.name}_\#{format}")
                    else
                      raise ArgumentError, "Invalid option: \#{options[:format]}"
                    end
                  end

                  self['#{k.name}']
                end
              EOF
              self.class_eval(src, __FILE__, line)

              SPATIAL_COLUMN_OUTPUT_FORMATS.reject { |f| f == 'geos' }.each do |f|
                src, line = <<-EOF, __LINE__ + 1
                  def #{k.name}_#{f}(*args)
                    @#{k.name}_#{f} ||= self.#{k.name}_geos.to_#{f}(*args) rescue nil
                  end
                EOF
                self.class_eval(src, __FILE__, line)
              end
            end
          end

          # Creates column accessors for geometry columns only.
          def create_geometry_column_accessors!(options = {})
            options = {
              :geometry_columns => true
            }.merge(options)

            create_spatial_column_accessors!(options)
          end

          # Creates column accessors for geometry columns only.
          def create_geography_column_accessors!(options = {})
            options = {
              :geography_columns => true
            }.merge(options)

            create_spatial_column_accessors!(options)
          end

          # Stubs for documentation purposes:

          # Returns a Geos::Geometry object.
          def __spatial_column_name_geos; end

          # Returns a hex-encoded WKB String.
          def __spatial_column_name_wkb; end

          # Returns a WKB String in binary.
          def __spatial_column_name_wkb_bin; end

          # Returns a WKT String.
          def __spatial_column_name_wkt; end

          # Returns a hex-encoded EWKB String.
          def __spatial_column_name_ewkb; end

          # Returns an EWKB String in binary.
          def __spatial_column_name_ewkb_bin; end

          # Returns an EWKT String.
          def __spatial_column_name_ewkt; end

          # An enhanced setter that tries to deduce how you're
          # setting the value. The setter can handle Geos::Geometry
          # objects, WKT, EWKT and WKB and EWKB in both hex and
          # binary.
          #
          # When dealing with SRIDs, you can have the SRID set
          # automatically on WKT by setting the value as
          # "SRID=default;GEOMETRY(...)", i.e.:
          #
          #  spatial_column_name = "SRID=default;POINT(1.0 1.0)"
          #
          # The SRID will be filled in automatically if available.
          # Note that we're only setting the SRID on the geometry,
          # but we're not doing any sort of re-projection or anything
          # of the sort. If you need to convert from one SRID to
          # another, you're stuck for the moment, but we'll be adding
          # support for reprojections/transoformations via proj4rb
          # soon.
          #
          # For WKB, you're better off manipulating the WKB directly
          # or using proper Geos geometry objects.
          def __spatial_column_name=(geom); end

          # An enhanced getter that accepts an options Hash or
          # String/Symbol that can be used to determine the output
          # format. In the options Hash, use :format, or set the
          # format directly as a String or Symbol.
          #
          # This basically allows you to do the following, which
          # are equivalent:
          #
          #  spatial_column_name(:wkt)
          #  spatial_column_name(:format => :wkt)
          #  spatial_column_name_wkt
          def __spatial_column_name(options = {}); end

          undef __spatial_column_name_geos
          undef __spatial_column_name_wkb
          undef __spatial_column_name_wkb_bin
          undef __spatial_column_name_wkt
          undef __spatial_column_name_ewkb
          undef __spatial_column_name_ewkb_bin
          undef __spatial_column_name_ewkt

          #undef __spatial_column_name_geojson
          #undef __spatial_column_name_geohash
          #undef __spatial_column_name_hexweb
          #undef __spatial_column_name_kml
          #undef __spatial_column_name_svg
          #undef __spatial_column_name_x3d
          #undef __spatial_column_name_lat_lon_text

          undef __spatial_column_name=
          undef __spatial_column_name
      end
    end

    # Alias for backwards compatibility.
    GeometryColumns = SpatialColumns
  end
end