require "ftools"

class Warpable < ActiveRecord::Base
  
  has_attachment :content_type => :image, 
		 #:storage => :file_system,:path_prefix => 'public/warpables', 
                 :storage => :s3, 
                 :max_size => 10.megabytes,
                 # :resize_to => '320x200>',
		:processor => :image_science,
                 :thumbnails => { :medium => '500x375', :small => '240x180', :thumb => '100x100>' }

  # validates_as_attachment

  def validate
    errors.add_to_base("You must choose a file to upload") unless self.filename
    
    unless self.filename == nil
      
      # Images should only be GIF, JPEG, or PNG
      [:content_type].each do |attr_name|
        enum = attachment_options[attr_name]
        unless enum.nil? || enum.include?(send(attr_name))
          errors.add_to_base("You can only upload images (GIF, JPEG, or PNG)")
        end
      end
      
      # Images should be less than 5 MB
      [:size].each do |attr_name|
        enum = attachment_options[attr_name]
        unless enum.nil? || enum.include?(send(attr_name))
          errors.add_to_base("Images should be smaller than 5 MB in size")
        end
      end
        
    end

  end 

  def nodes_array
    Node.find self.nodes.split(',')
  end

  # pixels per meter = pxperm 
  def generate_perspectival_distort(pxperm,path)
    # convert IMG_0777.JPG -virtual-pixel Transparent -distort Affine '0,0, 100,100  3072,2304 300,300  3072,0 300,150  0,2304 150,1800' test.png
    require 'net/http'
    
    working_directory = RAILS_ROOT+"/public/warps/"+path+"-working/"
    directory = RAILS_ROOT+"/public/warps/"+path+"/"
    Dir.mkdir(directory) unless (File.exists?(directory) && File.directory?(directory))
    Dir.mkdir(working_directory) unless (File.exists?(working_directory) && File.directory?(working_directory))

    local_location = working_directory+self.id.to_s+'-'+self.filename
    completed_local_location = directory+self.id.to_s+'.tif'
    geotiff_location = directory+self.id.to_s+'-geo.tif'

    northmost = self.nodes_array.first.lat
    southmost = self.nodes_array.first.lat
    westmost = self.nodes_array.first.lon
    eastmost = self.nodes_array.first.lon

    self.nodes_array.each do |node|
      northmost = node.lat if node.lat > northmost
      southmost = node.lat if node.lat < southmost
      westmost = node.lon if node.lon < westmost
      eastmost = node.lon if node.lon > eastmost
    end

    # puts northmost.to_s+','+southmost.to_s+','+westmost.to_s+','+eastmost.to_s
    
    scale = 20037508.34    
    y1 = pxperm*Cartagen.spherical_mercator_lat_to_y(northmost,scale)
    x1 = pxperm*Cartagen.spherical_mercator_lon_to_x(westmost,scale)
    y2 = pxperm*Cartagen.spherical_mercator_lat_to_y(southmost,scale)
    x2 = pxperm*Cartagen.spherical_mercator_lon_to_x(eastmost,scale)
    # puts x1.to_s+','+y1.to_s+','+x2.to_s+','+y2.to_s

    points = ""
    coordinates = ""
    first = true
  
#Value	0th Row	0th Column
#1	top	left side
#2	top	right side
#3	bottom	right side
#4	bottom	left side
#5	left side	top
#6	right side	top
#7	right side	bottom
#8	left side	bottom

    rotation = system('identify -format %[exif:Orientation] '+local_location)
    if rotation == 6
      source_corners = [[0,self.width],[0,0],[self.height,0],[self.height,self.width]]
    else
      source_corners = [[0,0],[self.height,0],[self.height,self.width],[0,self.width]]
    end
    self.nodes_array.each do |node|
      corner = source_corners.shift
      nx1 = corner[0]
      ny1 = corner[1]
      nx2 = -x1+(pxperm*Cartagen.spherical_mercator_lon_to_x(node.lon,scale))
      ny2 = y1-(pxperm*Cartagen.spherical_mercator_lat_to_y(node.lat,scale))
   
      points = points + '  ' unless first
      points = points + nx1.to_s + ',' + ny1.to_s + ' ' + nx2.to_i.to_s + ',' + ny2.to_i.to_s
      first = false
      # we need to find an origin; find northwestern-most point
      coordinates = coordinates+' -gcp '+nx1.to_s+', '+ny1.to_s+', '+node.lon.to_s + ', ' + node.lat.to_s
    end

    if (self.public_filename[0..3] == 'http')
      Net::HTTP.start('s3.amazonaws.com') { |http|
      #Net::HTTP.start('localhost') { |http|
        resp = http.get(self.public_filename)
        open(local_location, "wb") { |file|
          file.write(resp.body)
        }
      }
    else
      File.copy(RAILS_ROOT+'/public'+self.public_filename,local_location)
    end

    imageMagick = "convert -monitor -background transparent "
    imageMagick += "-matte -virtual-pixel transparent "
    imageMagick += "-distort Perspective '"+points+"' "
    imageMagick += "-crop "+(y1-y2).to_i.to_s+"x"+(-x1+x2).to_i.to_s+" "
    imageMagick += local_location+" "+completed_local_location
    puts imageMagick
    puts system(imageMagick)
    puts 'complete!'

    #gdal_translate = "gdal_translate -of GTiff -a_srs '+init=epsg:4326' "+coordinates+'  -co "TILED=NO" '+local_location+' '+completed_local_location
    #gdalwarp = 'gdalwarp -dstalpha -srcnodata 255 -dstnodata 0 -cblend 30 -of GTiff -t_srs EPSG:4326 '+completed_local_location+' '+geotiff_location
    #puts gdal_translate
    #system(gdal_translate)
    #puts gdalwarp
    #system(gdalwarp)
    
    # warp = Warp.new({:map_id => self.map_id,:warpable_id => self.id,:path => completed_local_location})
    [x1,y1]
  end

end


