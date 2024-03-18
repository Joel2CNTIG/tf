require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 


def average(arr)
  return arr.sum/arr.size
end

def timeout(time_arr)
  time_arr = time_arr.last(5)
  if time_arr.length == 5
    time_intervals = []
    compared_time = time_arr[0]
    time_arr.each do |time|
      new_time = time - compared_time
      time_intervals << new_time
    end
    if average(time_intervals) <= 1
      session[:status] = "toofast"
      redirect('/login')
    end
  end
end

def connect_db(path)
  return SQLite3::Database.new(path)
end

def before_all(db)
  if session[:cooldown] == true
    session[:time2] = Time.now
    if session[:time2] - session[:time1] > 5
      session[:cooldown] = false
    else
      unless request.path_info.include?('/cooldown')
      redirect('/../cooldown')
      end
    end
  end
  restricted_routes = ['/create']
  login_routes = ['/', '/login', '/post-login', '/post-register', '/post-guest', '/wrong_username_or_pwd', '/username_too_long', '/username_already_exists', '/post-too_long', '/cooldown']
  if session[:id] == nil && !login_routes.include?(request.path_info) && session[:tag] != "guest"
    session[:tag] = nil
    session[:username] = nil
    session[:password] = nil
    session[:status] = nil 
    redirect('/')
  end
  if !login_routes.include?(request.path_info) && session[:tag] != "guest" && session[:username] != db.execute("SELECT username FROM user WHERE id = ?", session[:id]).first["username"]
    session[:tag] = nil
    session[:username] = nil
    session[:password] = nil
    session[:status] = nil 
    redirect('/')
  end
  if session[:tag] == "guest" && restricted_routes.include?(request.path_info)
    redirect('/home')
  end
  if session[:tag] != "admin" && request.path_info.include?('/admin')
    redirect('/home')
  end
  if session[:tag] == nil && !login_routes.include?(request.path_info)
    redirect('/')
  end
end

def post_login(db, username, password)
  session[:time_arr] << Time.now
  timeout(session[:time_arr])
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
  
def post_register(db, username, password, password_again)
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

def post_create(db, id, title, description, price, keyword, keyword2, keyword3)
  if title == "" || description == "" || price == ""
    session[:status] = "create_error"
    redirect('/create')
  end
  keywords = []
  unless keyword == nil || keyword == ""
    keywords << keyword
  end
  unless keyword2 == nil || keyword2 == ""
    keywords << keyword2
  end
  unless keyword3 == nil || keyword3 == ""
    keywords << keyword3
  end
  db.execute("INSERT INTO projects (user_id, title, description, visits, price) VALUES (?,?,?,?,?)", id, title, description, 0, price)
  proj_id = db.execute("SELECT id FROM projects WHERE title = ?", title).first["id"]
  keywords.each do |word|
    key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
    db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", proj_id, key_id)
  end
  session[:status] = nil
  redirect('/home')
end

def post_edit(db, id, title, description, price, keyword1, keyword2, keyword3)
  keywords = []
  unless keyword1 == nil || keyword1 == ""
    keywords << keyword1
  end
  unless keyword2 == nil || keyword2 == ""
    keywords << keyword2
  end
  unless keyword3 == nil || keyword3 == ""
    keywords << keyword3
  end
  unless title == ""
    db.execute("UPDATE projects SET title = ? WHERE id = #{id}", title)
  end
  unless description == ""
    db.execute("UPDATE projects SET description = ? WHERE id = #{id}", description)
  end
  unless price == ""
    db.execute("UPDATE projects SET price = ? WHERE id = #{id}", price)
  end
  keywords.each do |word|
    key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
    db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", id, key_id)
  end
  redirect("/project/#{id}")
end

def post_settings_delete_account(db, id, username, password)
  compared_username = db.execute("SELECT username FROM user WHERE id = ?", id).first["username"]
  compared_password = db.execute("SELECT password FROM user WHERE id = ?", id).first["password"]
  if username == compared_username && BCrypt::Password.new(compared_password) == password && session[:tag] != "admin"
    project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
    project_ids.each do |projid|
      new_project_id = projid["id"]
      db.execute("DELETE FROM projects WHERE id = ?", new_project_id)
      db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", new_project_id)
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

def post_admin_delete_account(db, id)
  if id == "1"
    redirect('/admin')
  end
  project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
  project_ids.each do |projid|
    project_id = projid["id"]
    db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", project_id)
  end
  db.execute("DELETE FROM projects WHERE user_id = ?", id)
  db.execute("DELETE FROM user WHERE id = ?", id)
  redirect('/../admin/manage_accounts')
end

def keyid_array_to_title_array(arr)
  projid_array = []
  arr.each do |id|
    projid_array << @db.execute("SELECT project_id FROM project_keyword_relationship WHERE keyword_id = ?", id) 
  end
  titles = []
  projid_array.each do |idarray|
    idarray.each do |id|
      titles << @db.execute("SELECT title FROM projects WHERE id = ?", id["project_id"]).first
    end
  end
  return titles
end

def post_search(db, keyword1, keyword2, keyword3)
  if keyword1 == ""
    key1 = "none"
  else
    key1 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword1).first["id"]
  end
  if keyword2 == ""
    key2 = "none"
  else
    key2 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword2).first["id"]
  end
  if keyword3 == ""
    key3 = "none"
  else
    key3 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword3).first["id"]
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