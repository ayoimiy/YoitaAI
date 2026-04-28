
local Heap = {}
Heap.__index = Heap 

function Heap:new()
	local obj = {
		data={}
	}
	setmetatable(obj,self)
	return obj 
end

function Heap:push(priority,value)
	local d = self.data
	table.insert(d,{priority,value})
	--进行上浮操作
	local i = #d
	--当其小于
	while i>1 and d[math.floor(i/2)][1]> d[i][1]    do 
		d[math.floor(i/2)],d[i] = d[i],d[math.floor(i/2)]
		i = math.floor(i/2)
	end
end

function Heap:pop()
	local d = self.data
	if #d == 0 then return nil  end
	local top = d[1][2]
	local last = table.remove(d,#d)
	if #d>0 then
		d[1] = last
		local i = 1
		while true do
			local left = 2*i
			local right = 2*i+1
			local smallest =  i 
			if left <= #d and d[left][1] < d[smallest][1] then smallest= left end
			if right <= #d and d[right][1] < d[smallest][1] then smallest = right end   
			if smallest == i then break end
			d[smallest],d[i] = d[i],d[smallest]
			i = smallest			
		end		
	end
	return top 
end
function Heap:peek()
	return self.d[1] and self.d[1][2]	
end

function Heap:size()
	return #self.data	
end

function Heap:is_empty()
	return #self.data == 0 
end

return Heap