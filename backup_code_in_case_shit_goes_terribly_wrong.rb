require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 

before do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  restricted_routes = ['/account/:id', '/create']
  login_routes = ['/', '/login', '/post-login', '/post-register', '/post-guest', '/wrong_username_or_pwd', '/username_too_long', '/username_already_exists', '/post-too_long']
  if !login_routes.include?(request.path_info) && session[:tag] != "guest" && session[:username] != db.execute("SELECT username FROM user WHERE id = ?", session[:id]).first["username"]
    redirect('/')
    session[:tag] = nil
    session[:username] = nil
    session[:password] = nil
    session[:status] = nil 
  end
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
    session[:status] = "wrong_user_or_pwd"
    redirect('/login')
  end
end
  
post('/post-register') do
  username = params[:username]
  password = params[:pwd]
  password_again = params[:pwd_again]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  compared_username = db.execute("SELECT username FROM user WHERE username LIKE ?",username).first
  password_digest = BCrypt::Password.create(password)
  if username.length > 20
    session[:status] = "toolong"
    redirect('/')
  end
  forbidden_chars = [" ", ",", ":", ";", "?", "!", "]", "[", "&", "=", "}", "{", "%", "¤", "$", "#", "£", "'", "@", "ä", "å", "ö", "|", "<", ">"]
  forbidden_chars.each do |char|
    if username.include?(char)
      session[:status] = "forbiddenchar"
      redirect('/')
    end
  end
  if password_again == password
    if compared_username == nil 
      db.execute("INSERT INTO user (username, password) VALUES (?,?)",username, password_digest)
      session[:username] = username
      session[:password] = password
      session[:status] = nil
      if username == "admin" 
        session[:tag] = "admin"
      else
        session[:tag] = "user"
      end
      session[:id] = db.execute("SELECT id FROM user WHERE username = ?",username).first["id"]
      redirect('/home')
    else
      session[:status] = "alreadyexists"
      redirect('/')
    end
  else
    session[:status] = "nomatch"
    redirect('/')
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

before('/project/:id/delete') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  user_id = db.execute("SELECT user_id FROM projects WHERE id = ?", params[:id])
  if session[:id] != user_id && session[:tag] != "admin"
    redirect('/home')
  end
end

get('/project/:id/delete') do
  slim(:"/site/delete")
end

post('/project/:id/post-delete_post') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("DELETE FROM projects WHERE id = ?", params[:id])
  db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", params[:id])
  redirect('/home')
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

get('/admin/manage_accounts') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @users = @db.execute("SELECT username FROM user")
  slim(:"admin/manage_accounts")
end

get('/admin/manage_posts') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @posts = @db.execute("SELECT title, id FROM projects")
  slim(:"/admin/manage_posts")
end

get('/admin/delete_account/:id') do
  slim(:"/admin/delete_account")
end

post('/post-delete_keyword/:proj_id/:keyword_id') do
  proj_id = params[:proj_id]
  keyword_id = params[:keyword_id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("DELETE FROM project_keyword_relationship WHERE keyword_id = #{keyword_id} AND project_id = #{proj_id}")
  redirect("/project/#{proj_id}")
end

before('/settings/:id/*') do
  if params[:id].to_i != session[:id] && session[:tag] != "admin"
    redirect('/home')
  end
end

get('/settings/:id') do
  slim(:"accounts/settings")
end

get('/settings/:id/change_username') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  @username = db.execute("SELECT username FROM user WHERE id = ?", params[:id]).first["username"]
  slim(:"accounts/change_username")
end

post('/settings/:id/post-change_username') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("UPDATE user SET username = ? WHERE id = #{params[:id]}", params[:username])
  unless session[:tag] == "admin"
    session[:username] = params[:username]
  end
  redirect("/settings/#{params[:id]}")
end

get('/settings/:id/delete_account') do
  slim(:"/accounts/delete_account")
end

post('/settings/:id/post-delete_account') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  username = params[:username]
  password = params[:pwd]
  compared_username = db.execute("SELECT username FROM user WHERE id = ?", id).first["username"]
  compared_password = db.execute("SELECT password FROM user WHERE id = ?", id).first["password"]
  if username == compared_username && BCrypt::Password.new(compared_password) == password && session[:tag] != "admin"
    project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
    project_ids.each do |projid|
      id = projid["id"]
      db.execute("DELETE FROM projects WHERE id = ?", id)
      db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", id)
    end
    db.execute("DELETE FROM user WHERE id = ?", id)
    session[:username] = nil
    session[:password] = nil
    session[:tag] = nil
    session[:status] = nil
    redirect('/')
  else
    redirect("settings/#{id}/delete_account")
  end
end

post('/admin/:id/post-delete_account') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
  project_ids.each do |projid|
    project_id = projid["id"]
    db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", project_id)
  end
  db.execute("DELETE FROM projects WHERE user_id = ?", id)
  db.execute("DELETE FROM user WHERE id = ?", id)
  redirect('/../admin/manage_accounts')
end

get('/home/search/:key1/:key2/:key3') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @result = @db.execute("SELECT word FROM keywords")
  keyids = [params[:key1], params[:key2], params[:key3]]
  p keyids
  p @db.execute("SELECT id FROM keywords WHERE word = ?", "cooking").first["id"]
  project_ids = []
  keyids.each do |id|
    project_ids << @db.execute("SELECT project_id FROM project_keyword_relationship WHERE keyword_id = ?", id) 
  end
  @projects = []
  project_ids.each do |idarray|
    idarray.each do |id|
      @projects << @db.execute("SELECT title FROM projects WHERE id = ?", id["project_id"]).first
    end
  end
  if keyids == ["none", "none", "none"]
    @projects = @db.execute("SELECt title FROM projects")
  end
  @projects = @projects.uniq
  slim(:"/site/search")
end

post('/post-search') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  if params[:keyword] == ""
    key1 = "none"
  else
    key1 = db.execute("SELECT id FROM keywords WHERE word = ?", params[:keyword]).first["id"]
  end
  if params[:keyword2] == ""
    key2 = "none"
  else
    key2 = db.execute("SELECT id FROM keywords WHERE word = ?", params[:keyword2]).first["id"]
  end
  if params[:keyword3] == ""
    key3 = "none"
  else
    key3 = db.execute("SELECT id FROM keywords WHERE word = ?", params[:keyword3]).first["id"]
  end
  redirect("/home/search/#{key1}/#{key2}/#{key3}")
end

post('/post-logout') do
  session[:username] = nil
  session[:tag] = nil
  session[:password] = nil
  session[:status] = nil
  redirect('/')
end