require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 

get('/') do
    slim(:"accounts/register", layout: :login_layout)
end

get('/login') do
    slim(:"accounts/login", layout: :login_layout)
end

post('/post-login') do
  username = params[:username]
  password = params[:pwd]
  db = SQLite3::Database.new("db/user_info.db")
  db.results_as_hash = true
  result = db.execute("SELECT password FROM user WHERE username = ?",username).first
  if result != nil && BCrypt::Password.new(result["password"]) == password
    session[:username] = username
    session[:password] = password
    redirect('/home')
    if username == "admin" 
      session[:tag] = "admin"
    else
      session[:tag] = "user"
    end
    session[:id] = db.execute("SELECT id FROM user WHERE username = ?",username).first["id"]
  else
    redirect('/wrong_username_or_pwd')
  end
end
  
post('/post-register') do
  username = params[:username]
  password = params[:pwd]
  db = SQLite3::Database.new("db/user_info.db")
  db.results_as_hash = true
  compared_username = db.execute("SELECT username FROM user WHERE username LIKE ?",username).first
  password_digest = BCrypt::Password.create(password)
  if compared_username == nil
    db.execute("INSERT INTO user (username, password) VALUES (?,?)",username, password_digest)
    session[:username] = username
    session[:password] = password
    if username == "admin" 
      session[:tag] = "admin"
    else
      session[:tag] = "user"
    end
    session[:id] = db.execute("SELECT id FROM user WHERE username = ?",username).first["id"]
    redirect('/home')
  else
    redirect('/username_already_exists')
  end
end

post('/post-guest') do
  session[:username] = "guest"
  session[:tag] = "guest"
  redirect('/home')
end