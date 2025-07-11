script.on_init(function()
    storage.path_requests = storage.path_requests or {}
    storage.car_paths = storage.car_paths or {}
    storage.is_travelling = false
end)

script.on_configuration_changed(function(event)
    if event.mod_changes and event.mod_changes["VehicleValet"] then
        storage.path_requests = storage.path_requests or {}
        storage.car_paths = storage.car_paths or {}
        storage.is_travelling = false
    end
end)

-- helper: find nearest empty car to the player within reasonable distance
local function find_nearest_car(player, search_radius)
    local cars = player.surface.find_entities_filtered {
        position = player.position,
        radius = search_radius,
        name = "car",
        force = player.force
    }

    local closest, min_dist = nil, math.huge
    for _, car in ipairs(cars) do
        if not car.get_driver() and car.valid then
            local dist = ((car.position.x - player.position.x) ^ 2 + (car.position.y - player.position.y) ^ 2) ^ 0.5
            if dist < min_dist then
                min_dist = dist
                closest = car
            end
        end
    end
    if closest then
        player.print("VehicleValet: Closest car found at [" ..
                string.format("%.2f", closest.position.x) .. ", " ..
                string.format("%.2f", closest.position.y) .. "], distance = " ..
                string.format("%.2f", min_dist)
        )
    else
        player.print("VehicleValet: No car found within radius.")
    end

    return closest
end

local function box_size(box)
    local lt = box.left_top or box[1]
    local rb = box.right_bottom or box[2]
    local w = (rb.x or rb[1]) - (lt.x or lt[1])
    local h = (rb.y or rb[2]) - (lt.y or lt[2])
    return math.max(w, h)
end

local function calc_collision_box(car, mul)
    mul = mul or 1.0
    local size = box_size(car.prototype.collision_box) * mul
    return {
        left_top = { x = -size / 2, y = -size / 2 },
        right_bottom = { x = size / 2, y = size / 2 },
    }
end
local function get_world_bounding_box(car, mul)
    mul = mul or 1.0
    local size = box_size(car.prototype.collision_box) * mul
    local half = size / 2
    return {
        left_top = { x = car.position.x - half, y = car.position.y - half },
        right_bottom = { x = car.position.x + half, y = car.position.y + half }
    }
end
local function get_offscreen_spawn_position(player, car_proto)
    local surface = player.surface
    local buffer = 10
    local radius = 60 + buffer -- radius for offscreen spawn

    -- Try multiple directions
    local directions = {
        { dx = -radius, dy = 0 },    -- West
        { dx =  radius, dy = 0 },    -- East
        { dx = 0,        dy = -radius }, -- North
        { dx = 0,        dy =  radius }, -- South
        { dx = -radius,  dy = -radius }, -- NW
        { dx =  radius,  dy = -radius }, -- NE
        { dx = -radius,  dy =  radius }, -- SW
        { dx =  radius,  dy =  radius }, -- SE
    }

    for _, dir in ipairs(directions) do
        local candidate_pos = {
            x = player.position.x + dir.dx,
            y = player.position.y + dir.dy
        }

        if surface.can_place_entity{
            name = car_proto.name,
            position = candidate_pos,
            force = player.force
        } then
            return candidate_pos
        end
    end

    return nil
end

-- called when the player presses SHIFT + ENTER
script.on_event({ "vehicle-valet-return", "vehicle-valet-numpad-enter" }, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    -- check if player is already in a vehicle
    if player.vehicle and player.vehicle.valid then
        player.print("[color=red]Player already in a car![/color]")
        return
    end

    if storage.is_travelling then
        player.print("A car is already en route!")
        return
    end

    player.print("Calling car...")


    -- try screen search first
    -- Approximate screen size in tiles at max zoom out
    local screen_width_tiles = 100
    local screen_height_tiles = 80
    local screen_radius = math.max(screen_width_tiles, screen_height_tiles) / 2 + 10


    local car = find_nearest_car(player, screen_radius)
    if not car then
        -- expand to nearby range
        car = find_nearest_car(player, screen_radius + 50)
        if not car then
            -- expand to "global"
            car = find_nearest_car(player, screen_radius + 1000)
            if car then
                local fuel_inventory = car.get_fuel_inventory()
                if not fuel_inventory or fuel_inventory.is_empty() then
                    player.print("[color=red]Nearest car has no fuel![/color]")
                    return
                end

                -- teleport it just offscreen
                local safe_pos = get_offscreen_spawn_position(player, car.prototype)
                if safe_pos then
                    car.teleport(safe_pos)
                    player.print("[color=green]Car teleported![/color]")
                else
                    player.print("[color=red]No safe spawn location found near player![/color]")
                end
            end
        end
    end



    if not car then
        player.print("No available car found nearby.")
        return
    else -- car exists, check other stuff
        local fuel_inventory = car.get_fuel_inventory()
        if not fuel_inventory or fuel_inventory.is_empty() then
            player.print("[color=red]Nearest car has no fuel![/color]")
            return
        end
        if not car.bounding_box then
            player.print("Error: Invalid car or player position for pathfinding.")
            return
        end
    end



    local goal_position = {
    x = player.position.x,
    y = player.position.y
    }


    local box = get_world_bounding_box(car, 2)
    --rendering.draw_rectangle{
    --color = {r = 1, g = 0, b = 0},
    --width = 2,
    --filled = false,
    --left_top = box.left_top,
    --right_bottom = box.right_bottom,
    --surface = car.surface,
    --time_to_live = 60 * 5
    --}
--
--
--
    ---- start position - car
    --rendering.draw_circle{
    --color = {r = 0, g = 1, b = 0},
    --    radius = 0.5,
    --    filled = true,
    --    target = car.position,
    --    surface = car.surface,
    --    time_to_live = 60 * 5
    --}
    ---- goal - next to player
    --rendering.draw_circle{
    --    color = {r = 0, g = 0, b = 1},
    --    radius = 0.5,
    --    filled = true,
    --    target = goal_position,
    --    surface = car.surface,
    --    time_to_live = 60 * 5
    --}

    if car.surface.name ~= player.surface.name then
        player.print("[color=red]Car and player are on different surfaces![/color]")
        return
    end

     -- request a path from the car's current position to the player's position
    local path_id = car.surface.request_path {
        bounding_box = calc_collision_box(car, 2),
        collision_mask = car.prototype.collision_mask,
        start = car.position,
        goal = goal_position,
        force = car.force,
        radius = 7,
        entity_to_ignore = car,
        pathfind_flags = {
            allow_destroy_friendly_entities = false,
            cache = false,
            prefer_straight_paths = true,
            low_priority = false,
        },

    }
    -- store the car entity so we know which car this path is for
    storage.path_requests[path_id] = {
        car = car,
        player_index = player.index
    }
end)

-- called when Factorio finishes calculating a path
script.on_event(defines.events.on_script_path_request_finished, function(event)
    local request = storage.path_requests[event.id]
    storage.path_requests[event.id] = nil -- clean up

    if not request then return end
    local car = request.car
    local player = game.get_player(request.player_index)

    -- only continue if car is still valid and path was returned
    if not car or not car.valid or not event.path then
        if not car or not car.valid then
            player.print("No valid car found")
        end
        if not event.path then
            player.print("no valid path found")
        end
        if player then
        player.print("No car path found or available.")
        end
        return
    end
    if player then
        player.print("Car path found!")
    end



    ---- visualize path waypoints
    --for i, node in ipairs(event.path) do
    --    rendering.draw_circle{
    --        color = {r = 1, g = 1, b = 0},
    --        radius = 0.2,
    --        filled = true,
    --        target = node.position,
    --        surface = car.surface,
    --        time_to_live = 60 * 10
    --    }
--
    --    if i < #event.path then
    --        rendering.draw_line{
    --            color = {r = 1, g = 1, b = 0},
    --            width = 1,
    --            from = node.position,
    --            to = event.path[i + 1].position,
    --            surface = car.surface,
    --            time_to_live = 60 * 10
    --        }
    --    end
    --end



    -- assign dumy driver
    if not car.get_driver() then
        local dummy = car.surface.create_entity{
            name = "character",
            position = car.position,
            force = car.force
        }
        car.set_driver(dummy)
    end

    -- store path data so we can update movement each tick
    storage.car_paths[car.unit_number] = {
        car = car,
        path = event.path,
        index = 1, -- start at first waypoint
    }

    storage.is_travelling = true
end)

local function calc_orientation(posA, posB)
    local dx = posB.x - posA.x
    local dy = posB.y - posA.y
    return (math.atan2(dy, dx) / (2 * math.pi) + 0.25) % 1
end



-- every few ticks, move cars toward their next waypoint
script.on_event(defines.events.on_tick, function()
    for unit_number, data in pairs(storage.car_paths) do
        local car = data.car
        local path = data.path
        local i = data.index

        -- sanity check
        if not car.valid or not path[i] then
            if car.get_driver() and car.get_driver().name == "character" then
                car.get_driver().destroy()
            end
            storage.car_paths[unit_number] = nil
            goto continue
        end

        local target = path[i].position
        local pos = car.position
        local dx, dy = target.x - pos.x, target.y - pos.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < 0.5 then
            -- reached current waypoint; move to next
            data.index = i + 1
            if not path[data.index] then
                -- finished path
                if car.get_driver() and car.get_driver().name == "character" then
                    car.get_driver().destroy()
                end
                storage.car_paths[unit_number] = nil
                storage.is_travelling = false -- allow next call
            end
        else
            -- move toward waypoint
            -- factorio orientation is 0.0-1.0 where 0 is east, 0.25 is north, etc
            local move_step = 0.4
            local norm = math.sqrt(dx * dx + dy * dy)
            car.teleport{
                x = pos.x + (dx / norm) * move_step,
                y = pos.y + (dy / norm) * move_step
            }
            car.orientation = calc_orientation(pos, target)

        end
        ::continue::
    end
end)