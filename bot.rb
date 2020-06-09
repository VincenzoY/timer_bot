
# Set up a timer with a locked VC

require 'discordrb'
require 'sqlite3'
require 'dotenv/load'

@bot = Discordrb::Commands::CommandBot.new token: ENV['TOKEN'], prefix: '-'
@update_time = 60

# Invite url

puts "This bot's invite URL is #{@bot.invite_url}."
puts 'Click on it to invite it to your server.'

# Commands

@bot.message(content: 'Ping!') do |event|
    event.respond 'Pong!'
end

@bot.command :addtimer do |event, name, *args|
    permissions(event)
    return event.respond "Please input a name" if name == nil
    return event.respond "Please input a time" if args == []
    time = convert(args)
    return time unless time.is_a? Integer
    add_to_database(name, time)
    event.respond "Created Timer Successfully."
    track(event)
end

@bot.command :track do |event|
    permissions(event)
    event.respond "Bot is tracking."
    track(event)
end

@bot.command :updatetime do |event, *args|
    permissions(event)
    time = convert(args)
    return time unless time.is_a? Integer
    @update_time = time - Time.now.to_i
    track(event)
end

@bot.command :deletetimer do |event, name|
    permissions(event)
    begin
        channelID = @db.execute("SELECT channelID FROM time WHERE timerName = ?", name)[0]["channelID"]
        Discordrb::API::Channel.delete("#{@bot.token}", channelID) if event.server.channels.find{ |i| i.id == channelID}
        @db.execute "DELETE FROM time WHERE timerName=?", name
        event.respond "Deleted Successfully"
    rescue => e
        event.respond "No such timer found"
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
        track(event)
    elsif time < 0
        return "Finished"
    end
    mm, ss = time.divmod(60)
    hh, mm = mm.divmod(60)
    dd, hh = hh.divmod(24)
    return "%dd %dh %dm" % [dd, hh, mm]
end

def track(event)
    num = @db.execute("SELECT count(*) AS total FROM time")[0]["total"]
    num.times do |i|
        @db.execute ("SELECT * FROM time LIMIT 1 OFFSET #{i}") do |row|
            Discordrb::API::Channel.delete("#{@bot.token}", row["channelID"]) if event.server.channels.find{ |i| i.id == "#{row["channelID"]}".to_i }
            channel = event.server.create_channel(name = "#{row["timerName"]}: #{readable_time(event, row["time"], row["timerName"])}", type = 2)
            Discordrb::API::Channel.update_permission("#{@bot.token}", channel.id, event.server.id, 0, 1048576, 'role')
            @db.execute("UPDATE time SET channelID = ? WHERE timerName = ?", channel.id, row["timerName"])
        end
    end
    p @update_time
    sleep(@update_time)
    p "done"
    track(event)
end

def permissions(event)
    if event.user.defined_permission?(:administrator)
        return
    else
        event.respond "You do not have access to this bot."
        sleep(@update_time)
        track(event)
    end
end

# database
@db = SQLite3::Database.open "timer.db"
@db.results_as_hash = true
@db.execute "CREATE TABLE IF NOT EXISTS time(timerName STRING, time INT, channelID INT)"

def add_to_database(timerName, time)
    if @db.execute("SELECT 1 FROM time WHERE timerName = ?", timerName).length > 0
        return "That is already a timer"
    else
        @db.execute("INSERT INTO time (timerName, time) VALUES (?, ?)", timerName, time)
    end
end

@bot.run