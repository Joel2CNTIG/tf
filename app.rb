require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 

before do
  restricted_routes = ['/account/:id', '/create', '/admin']
  login_routes = ['/', '/login', '/post-login', '/post-register', '/post-guest']
  if session[:tag] == "guest" && restricted_routes.include?(request.path_info)
    redirect('/home')
  end
  if session[:tag] != "admin" && request.path_info == '/admin'
    redirect('/home')
  end
  if session[:tag] == nil && !login_routes.include?(request.path_info)
    redirect('/')
  end
end

def connect_db(path)
  return SQLite3::Database.new(path)
end

get('/') do
  slim(:"accounts/register", layout: :login_layout)
end

get('/login') do
  slim(:"accounts/login", layout: :login_layout)
end

post('/post-login') do
  username = params[:username]
  password = params[:pwd]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  result = db.execute("SELECT password FROM user WHERE username = ?",username).first
  if result != nil && BCrypt::Password.new(result["password"]) == password
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
    redirect('/wrong_username_or_pwd')
  end
end
  
post('/post-register') do
  username = params[:username]
  password = params[:pwd]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  compared_username = db.execute("SELECT username FROM user WHERE username LIKE ?",username).first
  password_digest = BCrypt::Password.create(password)
  if compared_username == nil && username.length < 20
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

get('/home') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @recent = @db.execute("SELECT title FROM projects ORDER BY id DESC LIMIT 5")
  p @result
  slim(:"site/home")
end

get('/account/:id') do
  @id = params[:id]
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @result = @db.execute("SELECT title FROM projects WHERE user_id = ?", @id)
  slim(:"site/account")
end

get('/create') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  @result = db.execute("SELECT word FROM keywords")
  slim(:"site/create")
end

post('/post-create') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  id = session[:id]
  title = params[:title]
  description = params[:description]
  keywords = []
  unless params[:keyword1] == nil
    keywords << params[:keyword1]
  end
  unless params[:keyword2] == nil
    keywords << params[:keyword2]
  end
  unless params[:keyword3] == nil
    keywords << params[:keyword3]
  end
end

get('/project/:id') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  unless session[:tag] == "guest"
    db.execute("UPDATE projects SET visits = visits + 1 WHERE id = ?", params[:id])
  end
  @username = db.execute("SELECT username FROM user WHERE id = projects.user_id")
  @title = db.execute("SELECT title FROM projects WHERE id = ?", params[:id])
  @description = db.execute("SELECT description FROM projects WHERE id = ?", params[:id])
  keyword_ids = db.execute("SELECT keyword_id FROM project_keyword_relationship WHERE project_id = ?", params[:id])
  @keywords = []
  keyword_id.each do |keyid|
    @keywords << db.execute("SELECT word FROM keywords WHERE id = ?", keyid).first
  end
  slim(:"site/project")
end

