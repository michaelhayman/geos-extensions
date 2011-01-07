
require 'rubygems'
require 'test/unit'
require File.join(File.dirname(__FILE__), %w{ .. lib geos_extensions })

puts "Ruby version #{RUBY_VERSION} - #{RbConfig::CONFIG['RUBY_INSTALL_NAME']}"
puts "GEOS version #{Geos::GEOS_VERSION}"
if defined?(Geos::FFIGeos)
  puts "Using #{Geos::FFIGeos.geos_library_paths.join(', ')}"
end

module TestHelper
	POINT_WKT = 'POINT(10 10.01)'
	POINT_EWKT = 'SRID=4326; POINT(10 10.01)'
	POINT_WKB = "0101000000000000000000244085EB51B81E052440"
	POINT_WKB_BIN = "\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x24\x40\x85\xEB\x51\xB8\x1E\x05\x24\x40"
	POINT_EWKB = "0101000020E6100000000000000000244085EB51B81E052440"
	POINT_EWKB_BIN = "\x01\x01\x00\x00\x20\xE6\x10\x00\x00\x00\x00\x00\x00\x00\x00\x24\x40\x85\xEB\x51\xB8\x1E\x05\x24\x40"
	POINT_G_LAT_LNG = "(10.01, 10)"
	POINT_G_LAT_LNG_URL_VALUE = "10.01,10"

	POLYGON_WKT = 'POLYGON((0 0, 1 1, 2.5 2.5, 5 5, 0 0))'
	POLYGON_EWKT = 'SRID=4326; POLYGON((0 0, 1 1, 2.5 2.5, 5 5, 0 0))'
	POLYGON_WKB = "
		0103000000010000000500000000000000000000000000000000000000000000000000F
		03F000000000000F03F0000000000000440000000000000044000000000000014400000
		00000000144000000000000000000000000000000000
	".gsub(/\s/, '')
	POLYGON_WKB_BIN = [
		"\x01\x03\x00\x00\x00\x01\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x00\x00",
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xF0\x3F\x00",
		"\x00\x00\x00\x00\x00\xF0\x3F\x00\x00\x00\x00\x00\x00\x04\x40\x00\x00\x00\x00",
		"\x00\x00\x04\x40\x00\x00\x00\x00\x00\x00\x14\x40\x00\x00\x00\x00\x00\x00\x14",
		"\x40\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
	].join
	POLYGON_EWKB = "
		0103000020E610000001000000050000000000000000000000000000000000000000000
		0000000F03F000000000000F03F00000000000004400000000000000440000000000000
		1440000000000000144000000000000000000000000000000000
	".gsub(/\s/, '')
	POLYGON_EWKB_BIN = [
		"\x01\x03\x00\x00\x20\xE6\x10\x00\x00\x01\x00\x00\x00\x05\x00\x00\x00",
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
		"\x00\x00\x00\x00\x00\xF0\x3F\x00\x00\x00\x00\x00\x00\xF0\x3F\x00\x00",
		"\x00\x00\x00\x00\x04\x40\x00\x00\x00\x00\x00\x00\x04\x40\x00\x00\x00",
		"\x00\x00\x00\x14\x40\x00\x00\x00\x00\x00\x00\x14\x40\x00\x00\x00\x00",
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
	].join

	POLYGON_WITH_INTERIOR_RING = "POLYGON((0 0, 5 0, 5 5, 0 5, 0 0),(4 4, 4 1, 1 1, 1 4, 4 4))"

	BOUNDS_G_LAT_LNG = "((0, 0), (5, 5))"

	def assert_saneness_of_point(point)
		assert_kind_of(Geos::Point, point)
		assert_equal(10.01, point.lat)
		assert_equal(10, point.lng)
	end

	def assert_saneness_of_polygon(polygon)
		assert_kind_of(Geos::Polygon, polygon)
		cs = polygon.exterior_ring.coord_seq
		assert_equal([
			[ 0, 0 ],
			[ 1, 1 ],
			[ 2.5, 2.5 ],
			[ 5, 5 ],
			[ 0, 0 ]
		], cs.to_a)
	end
end