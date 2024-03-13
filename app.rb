require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative 'model.rb'
enable :sessions 


before do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  before_all(db)
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
  post_login(db, username, password)
  {"name"=>"josef"}
end
  
post('/post-register') do
  username = params[:username]
  password = params[:pwd]
  password_again = params[:pwd_again]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  post_register(db, username, password, password_again)
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
  slim(:"site/home")
end

before('/account/:id') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  user_ids = db.execute("SELECT id FROM user")
  id_exists = false
  user_ids.each do |userid|
    userid = userid["id"]
    if userid == id.to_i
      id_exists = true
    end
  end
  if id_exists == false
    redirect('/home')
  end
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
  keyword1 = params[:keyword]
  keyword2 = params[:keyword2]
  keyword3 = params[:keyword3]
  post_create(db, id, title, description, price, keyword1, keyword2, keyword3)
end

get('/project/:id') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  unless session[:tag] == "guest"
    @db.execute("UPDATE projects SET visits = visits + 1 WHERE id = ?", params[:id])
  end
  @projinfo = @db.execute("SELECT * FROM projects WHERE id = ?", params[:id]).first
  @username = @db.execute("SELECT username FROM user WHERE id = ?", @projinfo["user_id"]).first["username"]
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
  keyword1 = params[:keyword]
  keyword2 = params[:keyword2]
  keyword3 = params[:keyword3]
  post_edit(db, id, title, description, price, keyword1, keyword2, keyword3)
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
  all_usernames = db.execute("SELECT username FROM user")
  all_usernames.each do |username|
    username = username["username"]
    if params[:username] == username
      session[:status] = "alreadyexists"
      redirect("/settings/#{params[:id]}/change_username")
    end
  end
  unless session[:tag] == "admin" 
    db.execute("UPDATE user SET username = ? WHERE id = #{params[:id]}", params[:username])
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
  post_settings_delete_account(db, id, username, password)
end

post('/admin/:id/post-delete_account') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  post_admin_delete_account(db, id)
end

get('/home/search/:key1/:key2/:key3') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @result = @db.execute("SELECT word FROM keywords")
  keyids = [params[:key1], params[:key2], params[:key3]]
  @projects = keyid_array_to_title_array(keyids)
  if keyids == ["none", "none", "none"]
    @projects = @db.execute("SELECt title FROM projects")
  end
  @projects = @projects.uniq
  slim(:"/site/search")
end

post('/post-search') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  keyword1 = params[:keyword]
  keyword2 = params[:keyword2]
  keyword3 = params[:keyword3]
  post_search(db, keyword1, keyword2, keyword3)
end

post('/post-logout') do
  session[:username] = nil
  session[:tag] = nil
  session[:password] = nil
  session[:status] = nil
  redirect('/')
end