require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 

before do
  restricted_routes = ['/account/:id', '/create']
  login_routes = ['/', '/login', '/post-login', '/post-register', '/post-guest', '/wrong_username_or_pwd', '/username_too_long']
  if session[:tag] == "guest" && restricted_routes.include?(request.path_info)
    redirect('/home')
  end
  if session[:tag] != "admin" && request.path_info == '/admin/*' 
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
  if username.length > 20
    redirect('/username_too_long')
  end
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

get('/home') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @recent = @db.execute("SELECT title FROM projects ORDER BY id DESC LIMIT 5")
  @popular = @db.execute("SELECT title FROM projects ORDER By visits DESC LIMIT 5")
  p @recent
  slim(:"site/home")
end

get('/account/:id') do
  @id = params[:id]
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @username = @db.execute("SELECT username FROM user WHERE id = ?", @id).first["username"]
  @result = @db.execute("SELECT title FROM projects WHERE user_id = ? ORDER BY id DESC", @id)
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
  price = params[:price]
  keywords = []
  unless params[:keyword] == nil || params[:keyword] == ""
    keywords << params[:keyword]
  end
  unless params[:keyword2] == nil || params[:keyword2] == ""
    keywords << params[:keyword2]
  end
  unless params[:keyword3] == nil || params[:keyword3] == ""
    keywords << params[:keyword3]
  end
  db.execute("INSERT INTO projects (user_id, title, description, visits, price) VALUES (?,?,?,?,?)", id, title, description, 0, price)
  proj_id = db.execute("SELECT id FROM projects WHERE title = ?", title).first["id"]
  keywords.each do |word|
    key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
    db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", proj_id, key_id)
  end
  redirect('/home')
end

get('/project/:id') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  unless session[:tag] == "guest"
    @db.execute("UPDATE projects SET visits = visits + 1 WHERE id = ?", params[:id])
  end
  @user_id = @db.execute("SELECT user_id FROM projects WHERE id = ?", params[:id]).first["user_id"]
  @username = @db.execute("SELECT username FROM user WHERE id = ?", @user_id).first["username"]
  @title = @db.execute("SELECT title FROM projects WHERE id = ?", params[:id]).first["title"]
  @proj_id = @db.execute("SELECT id FROM projects WHERE title = ?", @title).first["id"]
  @description = @db.execute("SELECT description FROM projects WHERE id = ?", params[:id]).first["description"]
  @price = @db.execute("SELECT price FROM projects WHERE id = ?", params[:id]).first["price"]
  keyword_ids = @db.execute("SELECT keyword_id FROM project_keyword_relationship WHERE project_id = ?", params[:id])
  @keywords = []
  keyword_ids.each do |keyid|
    @keywords << @db.execute("SELECT word FROM keywords WHERE id = ?", keyid["keyword_id"]).first["word"]
  end
  slim(:"site/project")
end

before('/project/:id/edit') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  id_list = db.execute('SELECT id FROM projects WHERE user_id = ?', session[:id])
  unless session[:tag] == "admin"
    id_list.each do |id|
      if id["id"] == params[:id]
        redirect('/home')
      end
    end
  end
end

get('/project/:id/edit') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @result = @db.execute("SELECT word FROM keywords")
  slim(:"site/edit")
end

post('/project/:id/post-edit') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  id = params[:id]
  title = params[:title]
  description = params[:description]
  price = params[:price]
  keywords = []
  unless params[:keyword] == nil || params[:keyword] == ""
    keywords << params[:keyword]
  end
  unless params[:keyword2] == nil || params[:keyword2] == ""
    keywords << params[:keyword2]
  end
  unless params[:keyword3] == nil || params[:keyword3] == ""
    keywords << params[:keyword3]
  end
  unless title == ""
    db.execute("UPDATE projects SET title = ? WHERE id = #{params[:id]}", title)
  end
  unless description == ""
    db.execute("UPDATE projects SET description = ? WHERE id = #{params[:id]}", description)
  end
  unless price == ""
    db.execute("UPDATE projects SET price = ? WHERE id = #{params[:id]}", price)
  end
  keywords.each do |word|
    key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
    db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", params[:id], key_id)
  end
  redirect("/project/#{params[:id]}")
end

get('/admin') do
  slim(:"admin/admin")
end

get('/admin/create_keyword') do
  slim(:"admin/create_keyword")
end

post('/post-create_keyword') do
  keyword = params[:keyword]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("INSERT INTO keywords (word) VALUES (?)",(keyword))
  redirect('/admin')
end

post('/post-delete_keyword/:proj_id/:keyword_id') do
  proj_id = params[:proj_id]
  keyword_id = params[:keyword_id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("DELETE FROM project_keyword_relationship WHERE keyword_id = #{keyword_id} AND project_id = #{proj_id}")
  redirect("/project/#{proj_id}")
end