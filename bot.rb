# Set up a timer with a locked VC

require 'discordrb'
require 'sqlite3'
require 'dotenv/load'

@command = "-"
@bot = Discordrb::Commands::CommandBot.new token: ENV['TOKEN'], prefix: "#{@command}"
@update_time = 10
@delete_time = 3600
@embed_color = "0018a1"
@busy = false
@invite = "https://discord.com/api/oauth2/authorize?client_id=720125551016280165&permissions=268435504&scope=bot"

# Invite url

puts "This bot's invite URL is #{@bot.invite_url}."
puts 'Click on it to invite it to your server.'
# Commands

@bot.ready() do
    run()
end

@bot.server_delete() do |event|
    @db.execute "DELETE FROM time WHERE serverID=?", event.server 
    @category_db.execute "DELETE FROM category WHERE serverID=?", event.server 
end

@bot.command :help do |event|
    event.channel.send_embed do |embed|
        embed.title = "Commands"
        embed.description = "Make Timers for your server. There is a max of five timers per server. Timers automatically delete one hour after completing their countdown"
        embed.color = "#{@embed_color}"
        embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: @bot.profile.avatar_url)
        fields = [Discordrb::Webhooks::EmbedField.new({name: "Create a Timer", value: "#{@command}addtimer (timer name) (Some combination of (int)d (int)h (int)m (int)s)\n__The timer name must be one word but you can use underscores and they will be turned into spaces__.\nExample: #{@command}addtimer Test\_Timer 5d 4m 2s"}),
                    Discordrb::Webhooks::EmbedField.new({name: "Delete a Timer", value: "#{@command}deletetimer (timer name)"}),
                    Discordrb::Webhooks::EmbedField.new({name: "List all Timers", value: "#{@command}list"}),
                    Discordrb::Webhooks::EmbedField.new({name: "Organize Timers in a Category", value: "#{@command}organize (true/false)"})]
        embed.fields = fields
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Created by Vincenzo#3091")
    end
end

@bot.command :list do |event|
    list = @db.execute("SELECT timerName FROM time WHERE serverID = #{event.server.id}")
    event.channel.send_embed do |embed|
        embed.title = "Active Timers"
        description = ""
        list.each do |timer|
            description += "#{timer["timerName"]}\n"
        end
        description = description[0..-2]
        embed.description = description
        embed.color = "#{@embed_color}"
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Created by Vincenzo#3091")
    end
end

@bot.command :addtimer do |event, name, *args|
    begin
        return "You do not have access to this bot." if permissions(event) == false
        if name == nil
            event.respond "Please input a name"
        elsif name.length > 50
            event.respond "That name is too long"
        elsif args == []
            event.respond "Please input a time"
        else
            name = name.gsub(/_/, " ")
            time = convert(args)
            if !(time.is_a? Integer)
                event.respond time
            else
                response = add_to_database(event.server.id, name, time)
                track_one(event, name) if response == "Created Timer Successfully."
                event.respond response
            end
        end
    rescue => e
        p e
        @db.execute "DELETE FROM time WHERE timerName=? AND serverID = ?", name, event.server.id
        event.respond "This bot does not have the correct permissons to run. Kick it and try again using the following invite link. #{@invite}"
    end
end

@bot.command :updatetime do |event, *args|
    return "You do not have access to this command." if event.user.id != 322845778127224832
    time = convert(args)
    return time unless time.is_a? Integer
    @update_time = time - Time.now.to_i
end

@bot.command :deletetime do |event, *args|
    return "You do not have access to this command." if event.user.id != 322845778127224832
    time = convert(args)
    return time unless time.is_a? Integer
    @deletetime = time - Time.now.to_i
end

@bot.command :deletetimer do |event, *args|
    return "You do not have access to this bot." if permissions(event) == false
    begin
        name = args.join(" ")
        name = name.gsub(/_/, " ")
        channelID = @db.execute("SELECT channelID FROM time WHERE timerName = ? AND serverID = ?", name, event.server.id)[0]["channelID"]
        begin
            Discordrb::API::Channel.delete("#{@bot.token}", channelID)
        rescue
        end
        @db.execute "DELETE FROM time WHERE timerName=? AND serverID = ?", name, event.server.id
        event.respond "Deleted Successfully"
    rescue => e
        event.respond "No such timer found"
    end
end

@bot.command :organize do |event, boolean|
    return "You do not have access to this bot." if permissions(event) == false
    return "Bot is busy at the moment. Try again in a few seconds" if @busy == true
    @busy = true
    if boolean == "true"
        begin
            # p "here"
            categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = ?", event.server.id)[0]["categoryID"]
            Discordrb::API::Channel.delete("#{@bot.token}", categoryID)
        rescue
            # p "no"
        end
        @category_db.execute "DELETE FROM category WHERE serverID=?", event.server.id
        begin
            category = event.server.create_channel(name = "Timer(s)", type = 4)
            Discordrb::API::Channel.update_permission("#{@bot.token}", category.id, event.server.id, 0, 1048576, 'role')
            Discordrb::API::Channel.update_permission("#{@bot.token}", category.id, @bot.profile.id, 1048576, 0, 'member')
            category.position=(0)
            @category_db.execute("INSERT INTO category (serverID, categoryID) VALUES (?, ?)", event.server.id, category.id)
            @db.execute("SELECT * FROM time WHERE serverID = #{event.server.id}") do |row|
                begin
                    Discordrb::API::Channel.delete("#{@bot.token}", row["channelID"])
                rescue
                    begin
                        Discordrb::API::Channel.delete("#{@bot.token}", @bot.find_channel(row["oldName"], @bot.server(row["serverID"]).name).first.id)
                    rescue
                    end
                end
                track_one(event, row["timerName"])
            end
            @busy = false
            event.respond "Organization is turned on."
        rescue
            @busy = false
            event.respond "This bot does not have the correct permissons to run. Kick it and try again using the following invite link. #{@invite}"
        end
    elsif boolean == "false"
        begin
            categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = ?", event.server.id)[0]["categoryID"]
            Discordrb::API::Channel.delete("#{@bot.token}", categoryID)
        rescue
        end
        @category_db.execute "DELETE FROM category WHERE serverID=?", event.server.id 
        @busy = false
        event.respond "Organization is turned off."
    else
        @busy = false
        event.respond "Sorry that is not a valid command."
    end
end

# convert mins, hours, days to int

def convert(args)
    interval = 0
    args.each do |time|
        timetype = time[-1]
        int = time[0...-1] 
        if int.to_i.to_s != int 
            return 'The command is invalid. Ensure the name is one word (read help command for more info).'
        elsif timetype == "s" 
            interval += int.to_i
        elsif timetype == "m" 
            interval += int.to_i*60
        elsif timetype == "h"
            interval += int.to_i*3600
        elsif timetype == "d"
            interval += int.to_i*86400
        else
            return 'The command is invalid. Ensure the time is valid (some combination of {int}d int{h} int{m} int{s}).'
        end
    end
    return "That's too long" if interval > 315576000
    return Time.now.to_i + interval
end

def readable_time(time, name, serverID)
    time -= Time.now.to_i
    if time <= (@delete_time*-1)
        channelID = @db.execute("SELECT channelID FROM time WHERE timerName = ? AND serverID = ?", name, serverID)[0]["channelID"]
        begin
            Discordrb::API::Channel.delete("#{@bot.token}", channelID)
        rescue
        end
        @db.execute "DELETE FROM time WHERE timerName=? AND serverID=?", name, serverID
        return "delete"
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
            Discordrb::API::Server.create_channel(token = @bot.token, server_id = event.server.id, name = "#{row["timerName"]}: #{readable_time(row["time"], row["timerName"], event.server.id)}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = categoryID, nsfw = false, rate_limit_per_user = 0, position = 0)
        else
            channel = event.server.create_channel(name = "#{row["timerName"]}: #{readable_time(row["time"], row["timerName"], event.server.id)}", type = 2)
            Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, @bot.profile.id, 1048576, 0, 'member')
            Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, event.server.id, 0, 1048576, 'role')
        end
        while channel == nil do 
            channel = @bot.find_channel("#{row["timerName"]}: #{readable_time(row["time"], row["timerName"], event.server.id)}", event.server.name).first
        end
        @db.execute("UPDATE time SET channelID = ?, oldName = ? WHERE timerName = ? AND serverID = ?", channel.id, "#{row["timerName"]}: #{readable_time(row["time"], row["timerName"], event.server.id)}", row["timerName"], "#{row["serverID"]}".to_i)
    end
end

def track()
    num = @db.execute("SELECT count(*) AS total FROM time")[0]["total"]
    num.times do |i|
        @db.execute ("SELECT * FROM time LIMIT 1 OFFSET #{i}") do |row|
            begin
                Discordrb::API::Channel.delete("#{@bot.token}", row["channelID"])
            rescue
                begin
                # p "glitch"
                Discordrb::API::Channel.delete("#{@bot.token}", @bot.find_channel(row["oldName"], @bot.server(row["serverID"]).name).first.id)
                rescue
                    # p "very bad"
                end
            end
            if @category_db.execute("SELECT 1 FROM category WHERE serverID = #{row["serverID"]}").length > 0
                categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = #{row["serverID"]}")[0]["categoryID"]
                readable_time = readable_time(row["time"], row["timerName"], row["serverID"])
                if readable_time != "delete"
                    begin
                        channel = @bot.channel(Discordrb::API::Server.create_channel(token = @bot.token, server_id = "#{row["serverID"]}".to_i, name = "#{row["timerName"]}: #{readable_time}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = categoryID, nsfw = false, rate_limit_per_user = 0, position = 0).to_s[8..25].to_i, @bot.server("#{row["serverID"]}"))
                    rescue
                        @category_db.execute "DELETE FROM category WHERE serverID=?", @bot.server(row["serverID"]).id
                        category = @bot.server(row["serverID"]).create_channel(name = "Timer(s)", type = 4)
                        Discordrb::API::Channel.update_permission("#{@bot.token}", category.id, @bot.server(row["serverID"]).id, 0, 1048576, 'role')
                        Discordrb::API::Channel.update_permission("#{@bot.token}", category.id, @bot.profile.id, 1048576, 0, 'member')
                        category.position=(0)
                        @category_db.execute("INSERT INTO category (serverID, categoryID) VALUES (?, ?)", @bot.server(row["serverID"]).id, category.id)
                        categoryID = @category_db.execute("SELECT categoryID FROM category WHERE serverID = #{row["serverID"]}")[0]["categoryID"]
                        channel = @bot.channel(Discordrb::API::Server.create_channel(token = @bot.token, server_id = "#{row["serverID"]}".to_i, name = "#{row["timerName"]}: #{readable_time}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = categoryID, nsfw = false, rate_limit_per_user = 0, position = 0).to_s[8..25].to_i, @bot.server("#{row["serverID"]}"))
                    end
                end
            else
                readable_time = readable_time(row["time"], row["timerName"], row["serverID"])
                if readable_time != "delete"
                    begin
                        channel = @bot.channel(Discordrb::API::Server.create_channel(token = @bot.token, server_id = "#{row["serverID"]}".to_i, name = "#{row["timerName"]}: #{readable_time}", type = 2, topic = "", bitrate = 64000, user_limit = 0, permission_overwrites = [], parent_id = nil, nsfw = false, rate_limit_per_user = 0, position = 0).to_s[8..25].to_i, @bot.server("#{row["serverID"]}"))
                        Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, @bot.profile.id, 1048576, 0, 'member')
                        Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, "#{row["serverID"]}".to_i, 0, 1048576, 'role')
                    rescue
                    end
                end
            end
            if readable_time != "delete"
                begin
                    @db.execute("UPDATE time SET channelID = ?, oldName = ? WHERE timerName = ? AND serverID = ?", channel.id, "#{row["timerName"]}: #{readable_time}", row["timerName"], "#{row["serverID"]}".to_i)
                rescue
                end
            end
        end
    end
end

def run()
    begin
        @a.kill
    rescue
    end
    @a = Thread.new do
        loop do
            track()
            sleep(@update_time)
        end
    end
end

def permissions(event)
    if event.user.permission?(:administrator)
        return true
    else
        return false
    end
end

# timer database
@db = SQLite3::Database.open "timer.db"
@db.results_as_hash = true
@db.execute "CREATE TABLE IF NOT EXISTS time(serverID INT, timerName STRING, time INT, channelID INT, oldName STRING)"

def add_to_database(serverID, timerName, time)
    if @db.execute("SELECT 1 FROM time WHERE timerName = ? AND serverID = #{serverID}", timerName).length > 0
        return "That is already a timer"
    elsif @db.execute("SELECT COUNT(serverID) FROM time WHERE serverID = #{serverID}").first["COUNT(serverID)"] >= 5
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
