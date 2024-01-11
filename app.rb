require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

get('/') do
    slim(:"accounts/register", layout: :login_layout)
end

get('/login') do
    slim(:"accounts/login", layout: :login_layout)
end

post('/post_register') do
end

post('/post_login') do
end