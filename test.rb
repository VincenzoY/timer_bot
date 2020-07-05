require 'discordrb'
require 'sqlite3'
require 'dotenv/load'

@command = "-"
@bot = Discordrb::Commands::CommandBot.new token: ENV['TOKEN'], prefix: "#{@command}"
@update_time = 600

@bot.ready() do
    begin
        @a.kill
    end
    run()
end

def run()
    @a = Thread.new do
        loop do
            puts "#{Time.now} - Working\n"
            sleep(@update_time)
        end
    end
end

@bot.run