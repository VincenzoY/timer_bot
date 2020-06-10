# Set up a timer with a locked VC

require 'discordrb'
require 'sqlite3'
require 'dotenv/load'

@command = "-"
@bot = Discordrb::Commands::CommandBot.new token: ENV['TOKEN'], prefix: "#{@command}"
@update_time = 300

# Invite url

puts "This bot's invite URL is #{@bot.invite_url}."
puts 'Click on it to invite it to your server.'

# Commands

@bot.command :help do |event|
    event.channel.send_embed do |embed|
        embed.title = "Commands"
        embed.description = "Make Timers for your server. There is a max of three timers per server."
        embed.color = "0018a1"
        embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: @bot.profile.avatar_url)
        fields = [Discordrb::Webhooks::EmbedField.new({name: "Create a Timer", value: "#{@command}addtimer [timer name (cannot have spaces)] [{Some combination of (int)d (int)h (int)m (int)s}]\n Example: #{@command}addtimer Test 5d 4m 2s"}),
                    Discordrb::Webhooks::EmbedField.new({name: "Delete a Timer", value: "#{@command}deletetimer [timer name (cannot have spaces)]"}),
                    Discordrb::Webhooks::EmbedField.new({name: "Organize Timers in a Category", value: "#{@command}organize [true/false]"})]
        embed.fields = fields
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Created by Vincent Y")
    end
end

@bot.command :addtimer do |event, name, *args|
    return "You do not have access to this bot." if permissions(event) == false
    return event.respond "Please input a name" if name == nil
    return event.respond "Please input a time" if args == []
    time = convert(args)
    return time unless time.is_a? Integer
    response = add_to_database(event.server.id, name, time)
    track_one(event, name) if response == "Created Timer Successfully."
    return response
end

@bot.command :track do |event|
    return "You do not have access to this command." if event.user.id != 322845778127224832
    p "working"
    event.respond "Bot is tracking."
    track(event)
end

@bot.command :updatetime do |event, *args|
    return "You do not have access to this command." if event.user.id != 322845778127224832
    time = convert(args)
    return time unless time.is_a? Integer
    @update_time = time - Time.now.to_i
end

@bot.command :deletetimer do |event, name|
    return "You do not have access to this bot." if permissions(event) == false
    begin
        channelID = @db.execute("SELECT channelID FROM time WHERE timerName = ? AND serverID = ?", name, event.server.id)[0]["channelID"]
        Discordrb::API::Channel.delete("#{@bot.token}", channelID) if event.server.channels.find{ |i| i.id == channelID}
        @db.execute "DELETE FROM time WHERE timerName=? AND serverID = ?", name, event.server.id
        event.respond "Deleted Successfully"
    rescue => e
        event.respond "No such timer found"
    end
end

@bot.command :organize do |event, boolean|
    return "You do not have access to this bot." if permissions(event) == false
    if boolean == "true"
        begin
            categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = ?", event.server.id)[0]["categoryID"]
            Discordrb::API::Channel.delete("#{@bot.token}", categoryID) if event.server.channels.find{ |i| i.id == categoryID}
        rescue
        end
        @category_db.execute "DELETE FROM category WHERE serverID=?", event.server.id 
        category = event.server.create_channel(name = "Timer(s)", type = 4)
        Discordrb::API::Channel.update_permission("#{@bot.token}", category.id, event.server.id, 0, 1048576, 'role')
        category.position=(0)
        @category_db.execute("INSERT INTO category (serverID, categoryID) VALUES (?, ?)", event.server.id, category.id)
        event.respond "Organization is turned on."
        @db.execute("SELECT * FROM time WHERE serverID = #{event.server.id}") do |row|
            Discordrb::API::Channel.delete("#{@bot.token}", row["channelID"]) if event.server.channels.find{ |i| i.id == row["channelID"]}
            track_one(event, row["timerName"])
        end
    elsif boolean == "false"
        begin
            categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = ?", event.server.id)[0]["categoryID"]
            Discordrb::API::Channel.delete("#{@bot.token}", categoryID) if event.server.channels.find{ |i| i.id == categoryID}
        rescue
        end
        @category_db.execute "DELETE FROM category WHERE serverID=?", event.server.id 
        event.respond "Organization is turned off."
    else
        event.respond "Sorry that is not a valid command."
    end
end

private

# convert mins, hours, days to int

def convert(args)
    interval = 0
    args.each do |time|
        timetype = time[-1]
        int = time[0...-1] 
        if int.to_i.to_s != int 
            return 'The command is invalid. Try again.'
        elsif timetype == "s" 
            interval += int.to_i
        elsif timetype == "m" 
            interval += int.to_i*60
        elsif timetype == "h"
            interval += int.to_i*3600
        elsif timetype == "d"
            interval += int.to_i*86400
        else
            return 'The command is invalid. Try again.'
        end
    end
    return Time.now.to_i + interval
end

def readable_time(event, time, name)
    time -= Time.now.to_i
    if time < -3600
        channelID = @db.execute("SELECT channelID FROM time WHERE timerName = ?", name)[0]["channelID"]
        Discordrb::API::Channel.delete("#{@bot.token}", channelID) if event.server.channels.find{ |i| i.id == channelID}
        @db.execute "DELETE FROM time WHERE timerName=?", name
    elsif time < 0
        return "Finished"
    end
    mm, ss = time.divmod(60)
    hh, mm = mm.divmod(60)
    dd, hh = hh.divmod(24)
    return "%dd %dh %dm" % [dd, hh, mm]
end

def track_one(event, name)
    @db.execute("SELECT * FROM time WHERE serverID = #{event.server.id} AND timerName = ?", name) do |row|
        if @category_db.execute("SELECT 1 FROM category WHERE serverID = #{event.server.id}").length > 0
            categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = #{event.server.id}")[0]["categoryID"]
            Discordrb::API::Server.create_channel(token = @bot.token, server_id = event.server.id, name = "#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = categoryID, nsfw = false, rate_limit_per_user = 0, position = 0)
        else
            channel = event.server.create_channel(name = "#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", type = 2)
            Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, event.server.id, 0, 1048576, 'role')
        end
        channel = nil
        while channel == nil do 
            channel = @bot.find_channel("#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", event.server.name).first
        end
        @db.execute("UPDATE time SET channelID = ? WHERE timerName = ?", channel.id, row["timerName"])
    end
end

def track(event)
    num = @db.execute("SELECT count(*) AS total FROM time WHERE serverID = #{event.server.id}")[0]["total"]
    num.times do |i|
        @db.execute ("SELECT * FROM time WHERE serverID = #{event.server.id} LIMIT 1 OFFSET #{i}") do |row|
            Discordrb::API::Channel.delete("#{@bot.token}", row["channelID"]) if event.server.channels.find{ |i| i.id == "#{row["channelID"]}".to_i }
            if @category_db.execute("SELECT 1 FROM category WHERE serverID = #{event.server.id}").length > 0
                categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = #{event.server.id}")[0]["categoryID"]
                Discordrb::API::Server.create_channel(token = @bot.token, server_id = event.server.id, name = "#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = categoryID, nsfw = false, rate_limit_per_user = 0, position = 0)
            else
                channel = event.server.create_channel(name = "#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", type = 2)
                Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, event.server.id, 0, 1048576, 'role')
            end
            channel = nil
            while channel == nil do 
                channel = @bot.find_channel("#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", event.server.name).first
            end
            @db.execute("UPDATE time SET channelID = ? WHERE timerName = ?", channel.id, row["timerName"])
        end
    end
    sleep(@update_time)
    track(event)
end

def permissions(event)
    if event.user.defined_permission?(:administrator)
        return true
    else
        return false
    end
end

# timer database
@db = SQLite3::Database.open "timer.db"
@db.results_as_hash = true
@db.execute "CREATE TABLE IF NOT EXISTS time(serverID INT, timerName STRING, time INT, channelID INT)"

def add_to_database(serverID, timerName, time)
    if @db.execute("SELECT 1 FROM time WHERE timerName = ? AND serverID = #{serverID}", timerName).length > 0
        return "That is already a timer"
    elsif @db.execute("SELECT COUNT(serverID) FROM time WHERE serverID = #{serverID}").first["COUNT(serverID)"] >= 3
        return "You have too many timers. Delete a different one first before adding another."
    else
        @db.execute("INSERT INTO time (serverID, timerName, time) VALUES (?, ?, ?)", serverID, timerName, time)
        return "Created Timer Successfully."
    end
end

# category database
@category_db = SQLite3::Database.open "category.db"
@category_db.results_as_hash = true
@category_db.execute "CREATE TABLE IF NOT EXISTS category(serverID INT, categoryID INT)"

@bot.run