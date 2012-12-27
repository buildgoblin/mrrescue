Map = {}
Map.__index = Map

local lg = love.graphics

local floor_files = {
	"1-1-1.lua",
	"1-2.lua",
	"2-1.lua",
	"2-2.lua"
}

function Map.create()
	local self = setmetatable({}, Map)

	local file = love.filesystem.load("maps/base.lua")()

	for i,v in ipairs(file.layers) do
		if v.name == "main" then
			self.data = v.data
			break
		end
	end
	self.width = file.width
	self.height = file.height

	self.front_batch = lg.newSpriteBatch(img.tiles, 256)
	self.back_batch  = lg.newSpriteBatch(img.tiles, 256)
	self.redraw = true

	self.viewX, self.viewY, self.viewW, self.viewH = 0,0,0,0

	self.objects = {}
	self.particles = {}
	self.enemies = {}
	self.humans = {}
	self.items = {}
	self.fire = {}
	for ix = 0,self.width-1 do
		self.fire[ix] = {}
	end

	self.background = img.night

	self:populate()

	return self
end

function Map:populate()
	self.rooms = {}
	self.starts = {}

	for i=1,3 do
		self:addFloor(i)
	end

	local start = table.random(self.starts)
	self.startx = start.x + 8
	self.starty = start.y + 173

	-- Add coolants
	for i=1,2 do
		local roomindex = math.random(#self.rooms)
		local room = self.rooms[roomindex]
		local pos = table.random(room.objects)

		table.insert(self.items, Item.create(room.x+pos.x, pos.y+room.y, "coolant"))
		table.remove(self.rooms, roomindex)
	end

	self.rooms = nil
	self.starts = nil
end

--- Updates all entities in the map and recreates
--  sprite batches if necessary
--  @param dt Time since last update in seconds
function Map:update(dt)
	-- Update entities
	for i=#self.objects,1,-1 do
		if self.objects[i].alive == false then
			table.remove(self.objects, i)
		else
			self.objects[i]:update(dt)
		end
	end

	-- Update enemies
	for i=#self.enemies,1,-1 do
		if self.enemies[i].alive == false then
			table.remove(self.enemies, i)
		else
			self.enemies[i]:update(dt)
		end
	end

	-- Update humans
	for i=#self.humans,1,-1 do
		if self.humans[i].alive == false then
			table.remove(self.humans, i)
		else
			self.humans[i]:update(dt)
		end
	end

	-- Update items
	for i=#self.items,1,-1 do
		if self.items[i].alive == false then
			table.remove(self.items, i)
		else
			self.items[i]:update(dt)
		end
	end

	-- Update particles
	for i=#self.particles,1,-1 do
		if self.particles[i].alive == false then
			table.remove(self.particles, i)
		else
			self.particles[i]:update(dt)
		end
	end

	-- Update fire
	for ix=0,self.width-1 do
		for iy=self.height-1,0,-1 do
			if self.fire[ix][iy] then
				if self.fire[ix][iy].alive == false then
					self.fire[ix][iy] = nil
					self:addParticle(BlackSmoke.create(ix*16+8,iy*16+8))
				else
					self.fire[ix][iy]:update(dt)
				end
			end
		end
	end

	-- Recreate sprite batches if redraw is set
	if self.redraw == true then
		self:fillBatch(self.back_batch,  function(id) return id > 64 end)
		self:fillBatch(self.front_batch, function(id) return id <= 64 end)
		self.redraw = false
	end
end

--- Adds a fire block if possible
function Map:addFire(x,y)
	if x < 3 or x > 37 then
		return
	end

	if self.fire[x][y] == nil then
		self.fire[x][y] = Fire.create(x,y,self)
	end
end

--- Checks if a tile is on fire
function Map:hasFire(x,y)
	return self.fire[x] and self.fire[x][y] ~= nil
end

function Map:getFire(x,y)
	return self.fire[x] and self.fire[x][y]
end

--- Sets the drawing range for the map
-- @param x X coordinate of upper left corner
-- @param y Y coordinate of upper left corner
-- @param w Width of screen
-- @param h Height of screen
function Map:setDrawRange(x,y,w,h)
	if x ~= self.viewX or y ~= self.viewY
	or w ~= self.viewW or h ~= self.viewH then
		self:forceRedraw()
	end

	self.viewX, self.viewY = x,y
	self.viewW, self.viewH = w,h
end

--- Draws the background layer of the map.
--  Includes background tiles, humans and enemies
function Map:drawBack()
	-- Draw background
	local xin = translate_x/(MAPW-WIDTH)
	local yin = translate_y/(MAPH-HEIGHT)
	lg.draw(self.background, translate_x-xin*(512-WIDTH), translate_y-yin*(228-HEIGHT))

	-- Draw back tiles
	lg.draw(self.back_batch, 0,0)

	-- Draw fire
	for iy=0,self.height-1 do
		for ix=0,self.width-1 do
			if self.fire[ix][iy] then
				self.fire[ix][iy]:drawBack()
			end
		end
	end

	-- Draw entities, enemies and particles
	for i,v in ipairs(self.humans) do
		v:draw() end
	for i,v in ipairs(self.enemies) do
		v:draw() end

	-- Draw front tiles
	lg.draw(self.front_batch, 0,0)
end

--- Draws the foreground layer of the map.
--  Includes everything in front of the player
--  like particles, objects and front tiles.
function Map:drawFront()
	-- Draw objects and particles
	for i,v in ipairs(self.objects) do
		v:draw() end
	for i,v in ipairs(self.items) do
		v:draw() end
	for i,v in ipairs(self.particles) do
		v:draw() end
	
	-- Draw front fire
	for iy=0,self.height-1 do
		for ix=0,self.width-1 do
			if self.fire[ix][iy] then
				self.fire[ix][iy]:drawFront()
			end
		end
	end
end

--- Fills a given sprite batch with all tiles
--  that pass a given test.
--  @param batch Sprite batch to fill
--  @param test Function on the id of a tile. Must return true or false.
function Map:fillBatch(batch, test)
	batch:clear()
	local sx = math.floor(self.viewX/16)
	local sy = math.floor(self.viewY/16)
	local ex = sx+math.ceil(self.viewW/16)
	local ey = sy+math.ceil(self.viewH/16)

	for iy = sy, ex do
		for ix = sx, ex do
			local id = self:get(ix,iy)
			if id and id > 0 and test(id) == true then
				batch:addq(quad.tile[self:get(ix,iy)], ix*16, iy*16)
			end
		end
	end
end

function Map:drawFireLight()
	local sx = math.floor(self.viewX/16)-2
	local sy = math.floor(self.viewY/16)-2
	local ex = sx+math.ceil(self.viewW/16)+2
	local ey = sy+math.ceil(self.viewH/16)+2

	for iy = sy, ex do
		for ix = sx, ex do
			if self.fire[ix] and self.fire[ix][iy] then
				local inst = self.fire[ix][iy]
				lg.drawq(img.light_fire, quad.light_fire[inst.flframe%5], inst.x-34, inst.y-42)
			end
		end
	end
end

--- Forces the map to redraw sprite batch next frame
function Map:forceRedraw()
	self.redraw = true
end

--- Adds rooms to a floor
-- @param floor Floor to fill. Value between 1 and 3.
function Map:addFloor(floor)
	local yoffset = 5*(floor-1) -- 0, 5 or 10

	local file = love.filesystem.load("maps/floors/"..table.random(floor_files))()
	for i,v in ipairs(file.layers) do
		-- Load tiles
		if v.name == "main" then
			for iy = 0,file.height-1 do
				for ix = 3,file.width-4 do
					local tile = v.data[iy*file.width+ix+1]
					self:set(ix,iy+yoffset, tile)
				end
			end
		end
	end
	-- Load objects
	for i,v in ipairs(file.layers) do
		if v.name == "objects" then
			for j,o in ipairs(v.objects) do
				if o.type == "door" then
					table.insert(self.objects, Door.create(o.x, o.y+yoffset*16, o.properties.dir))
				elseif o.type == "room" then
					o.y = o.y+yoffset*16
					table.insert(self.rooms, o)
					self:addRoom(o.x/16, o.y/16, o.width/16, o)
				elseif o.type == "start" and floor == 3 then
					table.insert(self.starts, o)
				end
			end
		end
	end
end

--- Fills the inside of a room with the contents of a room file.
-- @param x X position of room in tiles
-- @param y Y position of room in tiles
-- @param width Width of room in tiles
function Map:addRoom(x,y,width,room)
	local file = love.filesystem.load("maps/room/"..width.."/"..math.random(NUM_ROOMS[width])..".lua")()
	for i,v in ipairs(file.layers) do
		if v.name == "main" then
			for iy = 0,file.height-1 do
				for ix = 0,file.width-1 do
					if self:collideCell(x+ix, y+iy) == false then
						local tile = v.data[iy*file.width+ix+1]
						self:set(x+ix, y+iy, tile)
					end
				end
			end
		elseif v.name == "objects" then
			room.objects = v.objects
		end
	end

	local random = math.random(1,3)
	if random == 1 then
		local rx = math.random(x+1,x+width-2)*16+8
		table.insert(self.humans, Human.create(rx, (y+4)*16))
	elseif random == 2 then
		local rx = math.random(x+1, x+width-2)*16+8
		table.insert(self.enemies, NormalEnemy.create(rx, (y+4)*16))
	else
		local rx = math.random(x+1, x+width-2)*16+8
		table.insert(self.enemies, JumperEnemy.create(rx, (y+4)*16))
	end
end

--- Adds a particle to the map
-- @param particle Particle to add
function Map:addParticle(particle)
	table.insert(map.particles, particle)
end

--- Checks if a point is inside a solid block
-- @param x X coordinate of point
-- @param y Y coordinate of point
-- @return True if the point is solid
function Map:collidePoint(x,y)
	local cx = math.floor(x/16)
	local cy = math.floor(y/16)

	return self:collideCell(cx,cy)
end

--- Checks if a cell is solid
-- @param cx X coordinate of cell in tiles
-- @param cy Y coordinate of cell in tiles
function Map:collideCell(cx,cy)
	local tile = self:get(cx,cy)
	if tile and tile > 0 and tile < 64 then
		return true
	else
		return false
	end
end

--- Checks whether a cell can burn or not
-- @param cx X coordinate of cell
-- @param cy Y coordinate of cell
function Map:canBurnCell(cx,cy)
	if self:collideCell(cx,cy) == true then
		return false
	end
	local tile = self:get(cx,cy)
	if tile >= 255 and tile <= 256
	or tile >= 239 and tile <= 240 then
		return false
	end
	return true
end

--- Called when some object (stream, flying NPC...) collides
--  with a solid tile.
-- @param cx X coordinate of the cell
-- @param cy Y coordinate of the cell
function Map:hitCell(cx,cy,dir)
	local id = self:get(cx,cy)
	if id == 38 or id == 39 then
		self:destroyWindow(cx,cy,id,dir)
	end
end

--- Destroy a window and adds shards particle effect
--@param cx X-position of window
--@param cy Y-position of upper tile of window
--@param id ID of the tile that was hit triggered
--@param dir Direction of the water stream upon collision
function Map:destroyWindow(cx,cy,id,dir)
	if id == 38 then -- left lower window
		self:set(cx,cy-1, 239)
		self:set(cx,cy,   255)
		table.insert(self.particles, Shards.create(cx*16+6, (cy-1)*16, dir))
	elseif id == 39 then -- right lower window
		self:set(cx,cy-1, 240)
		self:set(cx,cy,   256)
		table.insert(self.particles, Shards.create(cx*16+10, (cy-1)*16, dir))
	end
	self:forceRedraw()
end

--- Returns the id of the tile (x,y)
function Map:get(x,y)
	if x < 0 or y < 0 or x > self.width or y > self.height then
		return 0
	else
		return self.data[y*self.width+x+1]
	end
end

--- Returns the id of the tile the point (x,y) belongs to
function Map:getPoint(x,y)
	local cx = math.floor(x/16)
	local cy = math.floor(y/16)
	return self:get(cx,cy)
end

--- Sets the id of the tile (x,y)
function Map:set(x,y,val)
	if x < 0 or y < 0 or x > self.width or y > self.height then
		return
	end
	self.data[y*self.width+x+1] = val
end

function Map:getWidth()
	return self.width
end

function Map:getHeight()
	return self.height
end

function Map:getStart()
	return self.startx, self.starty
end
