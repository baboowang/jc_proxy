# 脚本/样式文件合并压缩服务
 
## 接口
http://127.0.0.1:9001/proxy/{type}.{version}.{cachetime}/{resource_define_url.html}

*推荐是针服务放在其它web服务器之后*

### 参数
{type}	必须，值为js或css ,表明加载的资源类型
{version}	可选，资源的版本，值为自定义的字符串
{cachetime}	可选 ，默认为3600秒，表示缓存的时间（源服务合并结果的缓存时间及CDN的过期时间）
{resource_define_url.html}	需要全并资源定向的url，不包含http://的开头
 
### 例子

资源定义url: example.com/resource.html
 
* js合并文件：http://127.0.0.1:9001/proxy/js.v1.86400/example/resource.html
* css合并文件：http://127.0.0.1:9001/proxy/css.v1.86400/example/resource.html

### 作用
将页面引用的多个脚本或样式压缩，打包至一个请求，优化页面加载速度 。
将支持设置缓存时间和版本，可配合CDN使用。

