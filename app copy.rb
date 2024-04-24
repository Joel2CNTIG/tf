require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative 'model.rb'
enable :sessions 

include Model

# Runs before every route - checks authorization and login cooldowns
#
# @see Model#before_all
# @See Model#connect_db
before do
  if session[:time_arr] == nil
    session[:time_arr] = []
  end
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  before_all(db)
end

# Displays a register form
#
get('/') do
  slim(:"accounts/register", layout: :login_layout)
end

# Displays a login form
#
get('/login') do
  if session[:status] == "toofast"
    redirect('/cooldown')
  end
  slim(:"accounts/login", layout: :login_layout)
end

# Shows cooldown message
#
get('/cooldown') do
  slim(:"site/cooldown", layout: :login_layout)
end

# Attempts login
# @param [String] username, the entered username
# @param [String] pwd, the entered password
#
# @see Model#post_login
# @See Model#connect_db
post('/post-login') do
  username = params[:username]
  password = params[:pwd]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  result = db.execute("SELECT password FROM user WHERE username = ?",username).first
  post_login(db, username, password)
end
  
# Attemps to register user
# @param [String] username, the entered username
# @param [String] pwd, the entered password
# @param [String] pwd_again, the second entered password
#
# @see Model#post_register
# @See Model#connect_db
post('/post-register') do
  username = params[:username]
  password = params[:pwd]
  password_again = params[:pwd_again]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  post_register(db, username, password, password_again)
end

# Logs in as guest
#
post('/post-guest') do
  session[:username] = "guest"
  session[:tag] = "guest"
  redirect('/home')
end

# Shows a home page
# 
# @See Model#connect_db
get('/home') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @recent = @db.execute("SELECT title FROM projects ORDER BY id DESC LIMIT 5")
  @popular = @db.execute("SELECT title FROM projects ORDER By visits DESC LIMIT 5")
  slim(:"site/home")
end

# Runs before showing an account or project to make sure that they exists
# @param [Integer] id, the id associated with the account/project
# 
# @See Model#connect_db
['/account/:id', '/project/:id'].each do |path|
  before(path) do
    db = connect_db("db/user_info.db")
    db.results_as_hash = true
    if request.path_info.include?('/account')
      id = db.execute("SELECT id FROM user WHERE id = ?", params[:id])
    else
      id = db.execute("SELECT id FROM projects WHERE id = ?", params[:id])
    end
    if id == []
      redirect('/home')
    end
  end
end

# Displays an account aswell as a CRUD interface if the user has the necessary permissions
# @param [Integer] id, the id associated with the account
# 
# @See Model#connect_db
get('/account/:id') do
  @id = params[:id]
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @username = @db.execute("SELECT username FROM user WHERE id = ?", @id).first["username"]
  @result = @db.execute("SELECT title FROM projects WHERE user_id = ? ORDER BY id DESC", @id)
  slim(:"site/account")
end

# Create interface
# 
# @See Model#connect_db
get('/create') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  @result = db.execute("SELECT word FROM keywords")
  slim(:"site/create")
end

# Creates post and adds to database
# @param [String] title, title of the post
# @param [String] description, description of the post
# @param [Integer] price, price of the post
# @param [String] keyword, first selected keyword
# @param [String] keyword2, second selected keyword
# @param [String] keyword3, third selected keyword
#
# @See Model#post_create
# @See Model#connect_db
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

# Displays a post aswell as a CRUD interface if the user has the necessary permissions
# @param [Integer] id, the id associated with the post
#
# @See Model#connect_db
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

# Runs before showing a project edit-page, makes sure user has necessary permissions
# @param [Integer] id, id associated with the project
#
# @See Model#connect_db
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

# Shows an edit-project page
# @param [Integer] id, id associated with the project
#
# @See Model#connect_db
get('/project/:id/edit') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @result = @db.execute("SELECT word FROM keywords")
  slim(:"site/edit")
end

# Edits the post
# @param [Integer] id, id associated with the post
# @param [String] title, title of the post
# @param [String] description, description of the post
# @param [Integer] price, price of the post
# @param [String] keyword, first selected keyword
# @param [String] keyword2, second selected keyword
# @param [String] keyword3, third selected keyword
#
# @See Model#post_edit
# @See Model#connect_db
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

# Runs before opening a project delete form, makes sure user has permission to do so
# @param [Integer] id, id of post
#
# @See Model#connect_db
['/project/:id/delete', '/project/:id/post-delete_post'].each do |path|
  before(path) do
    db = connect_db("db/user_info.db")
    db.results_as_hash = true
    user_id = db.execute("SELECT user_id FROM projects WHERE id = ?", params[:id]).first["user_id"]
    if session[:id] != user_id && session[:tag] != "admin"
      redirect('/home')
    end
  end
end

# Shows a project delete form
# @param [Integer] id, id of project
get('/project/:id/delete') do
  slim(:"/site/delete")
end

# Deletes a project
# @param [Integer] id, id of project
# 
# @See Model#connect_db
post('/project/:id/post-delete_post') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("DELETE FROM projects WHERE id = ?", params[:id])
  db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", params[:id])
  redirect('/home')
end

# Displays a basic admin menu
#
get('/admin') do
  slim(:"admin/admin")
end

# Displays a keyword creation form
#
get('/admin/create_keyword') do
  slim(:"admin/create_keyword")
end

# Creates keyword
# @param [String] keyword, name of keyword to create
# 
# @See Model#connect_db
post('/admin/post-create_keyword') do
  keyword = params[:keyword]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("INSERT INTO keywords (word) VALUES (?)",(keyword))
  redirect('/admin')
end

# Shows all accounts aswell as crud-interface for them
# 
# @See Model#connect_db
get('/admin/manage_accounts') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @users = @db.execute("SELECT username FROM user")
  slim(:"admin/manage_accounts")
end

# Shows all posts aswell as crud interface for them
# 
# @See Model#connect_db
get('/admin/manage_posts') do
  @db = connect_db("db/user_info.db")
  @db.results_as_hash = true
  @posts = @db.execute("SELECT title, id FROM projects")
  slim(:"/admin/manage_posts")
end

# Account deletion form for admin account
# @param [Integer] id, id of account
get('/admin/delete_account/:id') do
  slim(:"/admin/delete_account")
end

# Deletes keyword from project
# @param [Integer] proj_id, id of project
# @param [Integer] keyword_id, id of keyword to delete
# 
# @See Model#connect_db
post('/post-delete_keyword/:proj_id/:keyword_id') do
  proj_id = params[:proj_id]
  keyword_id = params[:keyword_id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  db.execute("DELETE FROM project_keyword_relationship WHERE keyword_id = #{keyword_id} AND project_id = #{proj_id}")
  redirect("/project/#{proj_id}")
end

# Runs before all settings pages, makes sure user is authorized to view them
# @param [Integer] id, id of user corresponding with setting page
before('/settings/:id/*') do
  if params[:id].to_i != session[:id] && session[:tag] != "admin"
    redirect('/home')
  end
end

# Shows settings menu
# @param [Integer] id, user id
get('/settings/:id') do
  slim(:"accounts/settings")
end

# Shows change username form
# @param [Integer] id, user id
# 
# @See Model#connect_db
get('/settings/:id/edit_username') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  @username = db.execute("SELECT username FROM user WHERE id = ?", params[:id]).first["username"]
  slim(:"accounts/edit_username")
end

# Changes username
# @param [Integer] id, user id
# @param [String] username, username
# 
# @See Model#post_settings_change_username
# @See Model#connect_db
post('/settings/:id/post-edit_username') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  post_settings_change_username(db, params[:id], params[:username])
end

# Shows password change form
#
get('/settings/:id/edit_password') do
  slim(:"/accounts/edit_password")
end

# Changes password
# @param [Integer] id, user id
# @param [String] old_pwd, user's old password
# @param [String] pwd, user's new password
# @param [String] pwd_again, password input again
#
# @See Model#post_settings_change_password
# @See Model#connect_db
post('/settings/:id/post-edit_password') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  id = params[:id]
  old_pwd = params[:old_pwd]
  pwd = params[:pwd]
  pwd_again = params[:pwd_again]
  post_settings_change_password(db, id, pwd, old_pwd, pwd_again)
end

# Shows delete account form
#
get('/settings/:id/delete_account') do
  slim(:"/accounts/delete_account")
end

# Deletes account from settings
# @param [Integer] id, user id
# @param [String] username, username
# @param [String] password, password
# 
# @See Model#post_settings_delete_account
# @See Model#connect_db
post('/settings/:id/post-delete_account') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  username = params[:username]
  password = params[:pwd]
  post_settings_delete_account(db, id, username, password)
end

# Deletes account from admin
# @param [Integer] id, user id
#
# @See Model#post_admin_delete_account
# @See Model#connect_db
post('/admin/:id/post-delete_account') do
  id = params[:id]
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  post_admin_delete_account(db, id)
end

# Shows search form
# @param [Integer] key1, id for keyword 1
# @param [Integer] key2, id for keyword 2
# @param [Integer] key3, id for keyword 3
#
# @See Model#keyid_array_to_title_array
# @See Model#connect_db
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

# Searches for posts with keywords
# @param [String] keyword, keyword 1
# @param [String] keyword2, keyword 2
# @param [String] keyword3, keyword 3
#
# @See Model#post_search
# @See Model#connect_db
post('/post-search') do
  db = connect_db("db/user_info.db")
  db.results_as_hash = true
  keyword1 = params[:keyword]
  keyword2 = params[:keyword2]
  keyword3 = params[:keyword3]
  post_search(db, keyword1, keyword2, keyword3)
end

# Logs out user
# 
post('/post-logout') do
  session[:username] = nil
  session[:tag] = nil
  session[:password] = nil
  session[:status] = nil
  redirect('/')
end