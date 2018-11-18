/**
 * The MIT License (MIT)
 * Copyright © 2018 <Muke.Meng>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 * associated documentation files (the “Software”), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial
 * portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 * LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
 * OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
global abstract class RestService {
    //static mapping of enum and Http method.
    private static Map<String, String> methodMap = new Map<String, String>{
            'HTTPGET' => 'GET',
            'HTTPPOST' => 'POST',
            'HTTPDELETE' => 'DELETE',
            'HTTPPATCH' => 'PATCH',
            'HTTPPUT' => 'PUT'
    };
    //http method enum
    global enum HTTPMethod {
        HTTPGET, HTTPPOST, HTTPDELETE, HTTPPATCH, HTTPPUT
    }
    //Interface of apiService
    global interface ApiService {
        RuntimeContext handle(RuntimeContext runtimeContext);
    }
    /**
     * @author Muke.Meng (muke.meng#celnet.com.cn / 573647120#qq.com / +86 18366138308)
     * @date 2018-06-21
     * @description Api configuration to be extend.And implements configuration method.
     */
    global abstract class ApiConfiguration {
        global abstract void configuration();
        //filter matcher
        private RestService.URIMatcher FilterURIMatcher = new RestService.URIMatcher();
        //service matcher
        private RestService.URIMatcher ServiceURIMatcher = new RestService.URIMatcher();
        //aop matcher
        private RestService.URIMatcher AopURIMatcher = new RestService.URIMatcher();
        private ApiService handle404;
        global ApiConfiguration banding(RestService.ResourcesMapping resourcesMapping) {
            if(resourcesMapping.isFilter){
                FilterURIMatcher.addResources(resourcesMapping);
            }
            else if(resourcesMapping.isHandler){
                ServiceURIMatcher.addResources(resourcesMapping);
            }
            else if(resourcesMapping.isAOP){
                AopURIMatcher.addResources(resourcesMapping);
            }else{
                throw new RestServiceException('Unknown type exception. You must set type');
            }
            return this;
        }
        global ApiConfiguration set404Handler(RestService.ApiService handler){
            this.handle404 = handler;
            return this;
        }
        global void startService(){
            configuration();
            RuntimeContext runtimeContext = new runtimeContext(new requestBody(),new responseBody(),'Before');
            List<ApiService> services = FilterURIMatcher.getServices(runtimeContext.request.getMethod(),runtimeContext.request.getURI());
            runtimeContext = doService(services,runtimeContext);
            List<ApiService> aopServices = AopURIMatcher.getServices(runtimeContext.request.getMethod(),runtimeContext.request.getURI());
            runtimeContext = doService(aopServices,runtimeContext);
            if(!runtimeContext.process && aopServices.size()>0){
                handleResponse(runtimeContext);
                return;
            }
            services = ServiceURIMatcher.getServices(runtimeContext.request.getMethod(),runtimeContext.request.getURI());
            runtimeContext = doService(services,runtimeContext);
            runtimeContext.runtime='After';
            runtimeContext = doService(aopServices,runtimeContext);
            if(services.size()==0||services==null){
                if(handle404!=null){
                    runtimeContext = doService(new ApiService[]{handle404},runtimeContext);
                }else{
                    handleResponse(null);
                    return;
                }
            }
            handleResponse(runtimeContext);
        }
        private void handleResponse(RuntimeContext context){
            if(context==null){
                RestContext.response.statusCode = 404;
                RestContext.response.responseBody = Blob.valueOf('Not Found');
            }else{
                RestContext.response.statusCode = context.response.getStatusCode();
                RestContext.response.responseBody = context.response.body;
                for (String key : context.response.headers.keySet()) {
                    RestContext.response.addHeader(key,context.response.headers.get(key));
                }

            }
        }
        private RuntimeContext doService(List<ApiService> services,RuntimeContext runtimeContext){
            if(services==null||services.isEmpty()){
                return RuntimeContext;
            }
            for (ApiService apiService : services) {
                runtimeContext = apiService.handle(runtimeContext);
            }
            return runtimeContext;
        }
    }
    /**
     * @author Muke.Meng (muke.meng#celnet.com.cn / 573647120#qq.com / +86 18366138308)
     * @date 2018-06-21
     * @description To save URI and next all nodes with tree. Default root is "/" as a virtual root.
     */
    global class URIMatcher {
        //URI..root node as /
        public String resources;
        //All next nodes
        public List<URIMatcher> nexts;
        //Previous nodeQuoteTriggerHandler
        public URIMatcher prev;
        //If next node is a star node.The reference to it.
        public URIMatcher nextStarNode;
        //checked this node is or not a star node
        public Boolean isStar = false;
        //Saving all apiService handler for this node
        public Map<String, List<RestService.ApiService>> apiServices = new Map<String, List<RestService.ApiService>>();
        //default Constructor
        URIMatcher() {
            this.resources = '/';
        }
        //all parameters constructor
        URIMatcher(String path, String method, List<RestService.ApiService> services, URIMatcher prev) {
            this(path, prev);
            addServices(method, services);
        }
        //Main constructor
        URIMatcher(String path, URIMatcher prev) {
            this.resources = path;
            this.prev = prev;
            if(this.prev.nextStarNode!=null){
                throw new RestServiceException('If the resources is a star, It must be only one node.');
            }
            if (this.resources.equals('*')) {
                this.isStar = TRUE;
                this.prev.nextStarNode = this;
            }
        }
        //Banding services
        void addServices(String method, List<RestService.ApiService> services) {
            if (!this.apiServices.containsKey(method)) {
                this.apiServices.put(method, new List<RestService.ApiService>());
            }
            this.apiServices.get(method).addAll(services);
        }
        //public method to add Resources Mapping.
        public void addResources(RestService.ResourcesMapping resourcesMapping) {
            for (String str : resourcesMapping.URIs) {
                addResources(this, str.removeStart('/'), resourcesMapping.apiServices, resourcesMapping.Method);
            }
        }
        //Recursive adding resources.
        void addResources(URIMatcher thisnode, String path, List<RestService.ApiService> services, String method) {
            List<String> pts = path.split('/');
            if (String.isEmpty(path)) {
                return;
            }
            if (thisnode.nexts == NULL) {
                if (pts.size() == 1) {
                    thisnode.nexts = new URIMatcher[]{
                            new URIMatcher(path, method, services, thisnode)
                    };
                } else {
                    String pt = pts.get(0);
                    URIMatcher mt = new URIMatcher(pt, thisnode);
                    thisnode.nexts = new URIMatcher[]{
                            mt
                    };
                    addResources(mt, path.removeStart(pt + '/'), services, method);
                }
            } else {
                String pt = pts.get(0);
                Boolean hasNode = FALSE;
                for (URIMatcher mts : thisnode.nexts) {
                    if (mts.resources.equals(pt)) {
                        hasNode =TRUE;
                        if (pts.size() == 1) {
                            throw new RestServiceException('Duplicate URI:'+mts.resources);
                            //mts.addServices(method, services);
                        } else {
                            addResources(mts, path.removeStart(pt + '/'), services, method);
                        }
                    }
                }
                if(!hasNode){
                    if (pts.size() == 1) {
                        thisnode.nexts.add(
                                new URIMatcher(path, method, services, thisnode)
                        );
                    } else {
                        URIMatcher mt = new URIMatcher(pt, thisnode);
                        thisnode.nexts.add(mt);
                        addResources(mt, path.removeStart(pt + '/'), services, method);
                    }
                }
            }
        }
        //Get services be method and URI path
        List<RestService.ApiService> getServices(String method,String path) {
            String[] pth = path.split('/');
            if (String.isEmpty(pth.get(0))) {
                pth.remove(0);
            }
            URIMatcher matcher = getUriMatcher(this, pth);
            if (matcher == null) {
                return new List<RestService.ApiService>();
            }
            return matcher.apiServices.get(method);
        }
        //Recursive getting URIMatcher by path array.
        URIMatcher getUriMatcher(URIMatcher thisNode, String[] pth) {
            if (pth.size() == 0) {
                return thisNode;
            }
            if (thisNode == null||thisNode.nexts==null) {
                return null;
            }
            for (URIMatcher next : thisNode.nexts) {
                if (isMatch(next.resources, pth[0])) {
                    pth.remove(0);
                    return getUriMatcher(next, pth);
                }
            }
            return null;
        }
        //Check this path is or not matching. * means any thing.
        Boolean isMatch(String resources, String path) {
            return resources.equals(path) || resources.equals('*');
        }
    }

    global class ResourcesMapping {
        private Boolean isAOP = FALSE;
        private Boolean isFilter = FALSE;
        private Boolean isHandler = FALSE;
        private Set<String> URIs = new Set<String>();
        private String Method;
        protected List<RestService.ApiService> apiServices = new List<RestService.ApiService>();

        global ResourcesMapping setMethod(httpMethod method) {
            this.Method = methodMap.get(method.name());
            return this;
        }
        global ResourcesMapping setURI(String URI) {
            this.URIs.add(URI);
            return this;
        }
        global ResourcesMapping setAsAOP() {
            this.isAOP = TRUE;
            this.isFilter = FALSE;
            this.isHandler = FALSE;
            return this;
        }
        global ResourcesMapping setAsFilter() {
            this.isAOP = FALSE;
            this.isFilter = TRUE;
            this.isHandler = FALSE;
            return this;
        }
        global ResourcesMapping setAsService() {
            this.isAOP = FALSE;
            this.isFilter = FALSE;
            this.isHandler = TRUE;
            return this;
        }
        global ResourcesMapping addService(RestService.ApiService service) {
            this.apiServices.add(service);
            return this;
        }
    }

    global class RequestBody {
        RequestBody() {
            this.URI = RestContext.request.requestURI;
            this.headers = RestContext.request.headers;
            this.params = RestContext.request.params;
            this.body = RestContext.request.requestBody;
            this.method = RestContext.request.httpMethod;
        }
        private Map<String, String> headers;
        private Map<String, String> params;
        private String URI;
        private Blob body;
        private String method;
        global Map<String, String> getParam() {
            return this.params.clone();
        }
        global void setParams(Map<String, String> params) {
            this.params = params;
        }
        global void putParam(String key, String value) {
            this.params.put(key, value);
        }
        global String removeParam(String key) {
            return this.params.remove(key);
        }
        global String getMethod(){
            return this.method;
        }

        global void setBody(Blob body) {
            this.body = body;
        }
        global Blob getBody() {
            return this.body;
        }

        global Map<String, String> getHeader() {
            return this.headers.clone();
        }
        global void setHeaders(Map<String, String> headers) {
            this.headers = headers;
        }
        global void putHeader(String key, String value) {
            this.headers.put(key, value);
        }
        global String removeHeader(String key) {
            return this.headers.remove(key);
        }
        global String getURI() {
            return this.URI;
        }
    }
    global class ResponseBody {
        ResponseBody(){
            this(null);
        }
        global ResponseBody(Blob body) {
            this(200, body);
        }
        global responseBody(Integer statusCode, Blob body) {
            this(statusCode, body, new Map<String, String>());
        }
        global responseBody(Blob body, Map<String, String> headers) {
            this(200, body, headers);
        }
        global responseBody(Integer statusCode, Blob body, Map<String, String> headers) {
            this.statusCode = statusCode == null ? 200 : statusCode;
            this.body = body;
            this.headers = headers == null ? new Map<String, String>() : headers;
        }

        global responseBody addHeader(String key, String value) {
            this.headers.put(key, value);
            return this;
        }
        private Blob body;
        private Integer statusCode;
        private Map<String, String> headers;

        global Blob getBody() {
            return this.body;
        }
        global void setBody(Blob body) {
            this.body = body;
        }

        global Integer getStatusCode() {
            return this.statusCode;
        }
        global void setStatusCode(Integer statusCode) {
            this.statusCode = statusCode;
        }

        global Map<String, String> getHeaders() {
            return this.headers.clone();
        }
        global void setHeaders(Map<String, String> headers) {
            this.headers = headers;
        }
        global void putHeader(String key, String value) {
            this.headers.put(key, value);
        }
        global String removeHeader(String key) {
            return this.headers.remove(key);
        }
    }
    global class RuntimeContext {
        RuntimeContext(RequestBody request, ResponseBody response, String runtime) {
            this.request = request;
            this.response = response;
            this.runtime = runtime;
        }
        global RequestBody request;
        global ResponseBody response;
        protected String runtime;//before after
        protected Boolean process = FALSE;
        global String getRuntime() {
            return this.runtime;
        }
        global void process() {
            this.process = TRUE;
        }
    }


    private class RestServiceException extends Exception {
    }

    private class LogServices {
    }
}
