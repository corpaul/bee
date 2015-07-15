module Bee
  class GDFToCsvLoader < Loader

    include LogUtils

    def initialize(config)
      super(config.get(:gdf_file), config)

      @zone = :no_zone
      @types = []
      @depends_edges = Hash.new
    end

    def check_zone(row, zone)
      case row
      when /^\s*nodedef>\s/
        zone = :node_zone
      when /^\s*edgedef>\s/
        zone = :edge_zone
      end

      return zone
    end

    def process_value(type, val)
      # Special handling for time variables (since they are lists)
      case type.intern
      when :totalusertime,:totalsystemtime,:totalelapsedtime,:ownusertime,:ownsystemtime,:ownelapsedtime

        # Strip away square brackets
        val.gsub!(/[\[\]]/, "")
        if (val.empty?)
          val = 0
        else
          val = val.split(";")
          if ([:totalelapsedtime,:ownelapsedtime].include?(type.intern))
            val = val.inject(0.0) {|sum,x|
              mins,secs = x.split(":")
              sum + 60*mins.to_f + secs.to_f
            }
          else
            val = val.map(&:to_f).inject(0.0, :+)
          end
        end
      end

      return val
    end

    def node(row_spl)
      # Skip uninteresting nodes
      return if (isJunk(row_spl[0]))

      @logger.info("Adding node #{row_spl[0]}")

      fname = "#{row_spl[9]}/#{row_spl[10]}"
      node = @writer.addNode(row_spl[0], "gdf", "", "", fname=fname)
      #do |n|
      #  row_spl.size.times do |i|
      #    @writer.addProperty(n, @types[i].intern, process_value(@types[i], row_spl[i]))
      #    @writer.addLabel(n, :gdf)
      #  end

        # implicit node check
      #  @writer.addProperty(n, :implicit, true)

        # Add full filename
      #  @writer.addProperty(n, :nid,
      #                      "#{@writer.getProperty(n, :dir)}/#{@writer.getProperty(n, :base)}")

        # Check if it is an internal path
      #  @writer.addProperty(n, :internal,
      #                      @writer.getProperty(n, :nid).start_with?("<root>") ? 1 : 0)

        # add node to depends_edges cache
        @depends_edges[node.id] = Hash.new
    end

    def edge_exists(from, to)
      if @depends_edges.has_key?(@writer.getProperty(from, :nid))
        return @depends_edges.has_key?(@writer.getProperty(to, :nid))
      end
      return false
    end

    def edge(row_spl)
      # Skip uninteresting nodes
      return if (isJunk(row_spl[0]) or isJunk(row_spl[1]))

      # Find the nodes by name
      from = row_spl[0]
      to = row_spl[1]

      # check if edge is implicit
      is_implicit = row_spl[6].eql?("1")

      @writer.addEdge(from, to, "depends")

      @logger.info("Adding depends edge from #{from} to #{to}")

      @depends_edges[@writer.getNode(from).id][@writer.getNode(to).id] = true

      #if (!is_implicit)
       # @logger.info("setting implicit property for #{row_spl[0]} and #{row_spl[1]}")
       # @writer.addProperty(from, :implicit, false)
       # @writer.addProperty(to, :implicit, false)
      #end
    end

    def handle_row(row)
      @logger.debug("Processing: #{row}")
      @zone = check_zone(row, @zone)

      case row
      when /^\s*nodedef>\s/
        @types = row.gsub(/^\s*nodedef>\s/, "").split(",").collect {|x| x.gsub(/\s.*$/, "")}
      when /^\s*edgedef>\s/
        @types = row.gsub(/^\s*edgedef>\s/, "").split(",").collect {|x| x.gsub(/\s.*$/, "")}
      else
        # Check that the split length matches the definition length
        row_spl = row.split(",")
        if (row_spl.size != @types.size)
          fatalAndRaise("Row splits have #{row_spl.size} elements while definition specifies #{@types.size}")
        end

        case @zone
        when :node_zone
          node(row_spl)

        when :edge_zone
          edge(row_spl)

        else
          fatalAndRaise("Row '#{row}' in an unrecognized zone of the file")
        end
      end
    end

    def load_hook
      @logger.info("=== STARTING GDFToCsvLoader ===")

      cnt = 0

      total_cnt = %x{wc -l #{@fname}}.split.first.to_i

      @writer.setHeaders("gdf")

      File.foreach(@fname) do |row|
        row.strip!
        handle_row(row)
        cnt  = cnt+1
        if (cnt % 10000 == 0)
          puts "Row: #{cnt}/#{total_cnt}"
        end
      end
      @logger.info("=== FINISHED GDFLoader ===")
    end
  end
end
